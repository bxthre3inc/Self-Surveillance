package com.selfsurveillance.viewer.ui.viewmodel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Environment
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.selfsurveillance.viewer.data.repository.SurveillanceRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject

data class ScreenMirrorUiState(
    val currentFrame: Bitmap?    = null,
    val isConnected: Boolean     = false,
    val isRecording: Boolean     = false,
    val recordingPath: String?   = null,
    val fps: Float               = 0f,
    val frameCount: Int          = 0,
    val error: String?           = null
)

@HiltViewModel
class ScreenMirrorViewModel @Inject constructor(
    private val repo: SurveillanceRepository,
    @ApplicationContext private val context: Context
) : ViewModel() {

    private val _state = MutableStateFlow(ScreenMirrorUiState())
    val state: StateFlow<ScreenMirrorUiState> = _state

    private var streamJob: Job? = null

    // Recording state
    private var encoder: MediaCodec?   = null
    private var muxer: MediaMuxer?     = null
    private var videoTrackIndex = -1
    private var encoderStarted = false
    private var recordWidth  = 0
    private var recordHeight = 0
    private var presentationTimeUs = 0L

    // FPS tracking
    private var lastFpsTime = System.currentTimeMillis()
    private var framesSinceLastFps = 0

    fun connect() {
        streamJob?.cancel()
        streamJob = viewModelScope.launch {
            _state.value = _state.value.copy(isConnected = false, error = null, frameCount = 0)
            repo.screenFrames()
                .catch { e -> _state.value = _state.value.copy(error = e.message, isConnected = false) }
                .collect { jpegBytes -> processFrame(jpegBytes) }
        }
    }

    fun disconnect() {
        streamJob?.cancel()
        if (_state.value.isRecording) stopRecording()
        _state.value = _state.value.copy(isConnected = false, currentFrame = null)
    }

    fun startRecording() {
        val frame = _state.value.currentFrame ?: return
        viewModelScope.launch(Dispatchers.IO) {
            setupEncoder(frame.width, frame.height)
            _state.value = _state.value.copy(isRecording = true)
        }
    }

    fun stopRecording() {
        viewModelScope.launch(Dispatchers.IO) {
            finalizeRecording()
            _state.value = _state.value.copy(isRecording = false)
        }
    }

    // MARK: - Frame processing

    private suspend fun processFrame(jpegBytes: ByteArray) = withContext(Dispatchers.Default) {
        val bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size) ?: return@withContext

        // FPS counter
        framesSinceLastFps++
        val now = System.currentTimeMillis()
        val elapsed = now - lastFpsTime
        val fps = if (elapsed >= 1000) {
            val f = framesSinceLastFps * 1000f / elapsed
            framesSinceLastFps = 0
            lastFpsTime = now
            f
        } else _state.value.fps

        _state.value = _state.value.copy(
            currentFrame = bitmap,
            isConnected  = true,
            fps          = fps,
            frameCount   = _state.value.frameCount + 1
        )

        // Feed into encoder if recording
        if (_state.value.isRecording) {
            encodeFrame(bitmap)
        }
    }

    // MARK: - MediaCodec H.264 encoding

    private fun setupEncoder(width: Int, height: Int) {
        // Round dimensions to multiples of 16 (codec requirement)
        recordWidth  = ((width  + 15) / 16) * 16
        recordHeight = ((height + 15) / 16) * 16

        val format = MediaFormat.createVideoFormat("video/avc", recordWidth, recordHeight).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE,    2_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE,  15)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }

        val outputFile = createOutputFile()
        muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        _state.value = _state.value.copy(recordingPath = outputFile.absolutePath)

        encoder = MediaCodec.createEncoderByType("video/avc").also {
            it.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            it.start()
        }
        encoderStarted = true
        presentationTimeUs = 0L
    }

    private fun encodeFrame(bitmap: Bitmap) {
        val codec = encoder ?: return
        val scaledBitmap = if (bitmap.width != recordWidth || bitmap.height != recordHeight) {
            Bitmap.createScaledBitmap(bitmap, recordWidth, recordHeight, false)
        } else bitmap

        val yuv = bitmapToYuv420(scaledBitmap)

        val inputIndex = codec.dequeueInputBuffer(10_000)
        if (inputIndex >= 0) {
            val inputBuffer = codec.getInputBuffer(inputIndex) ?: return
            inputBuffer.clear()
            inputBuffer.put(yuv)
            presentationTimeUs += 66_666  // ~15 fps
            codec.queueInputBuffer(inputIndex, 0, yuv.size, presentationTimeUs, 0)
        }

        drainEncoder(false)
    }

    private fun finalizeRecording() {
        val codec = encoder ?: return
        val inputIndex = codec.dequeueInputBuffer(10_000)
        if (inputIndex >= 0) {
            codec.queueInputBuffer(inputIndex, 0, 0, presentationTimeUs,
                MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        }
        drainEncoder(true)
        codec.stop()
        codec.release()
        muxer?.stop()
        muxer?.release()
        encoder       = null
        muxer         = null
        encoderStarted = false
        videoTrackIndex = -1
    }

    private fun drainEncoder(endOfStream: Boolean) {
        val codec  = encoder ?: return
        val muxer_ = muxer   ?: return
        val info   = MediaCodec.BufferInfo()

        while (true) {
            val outputIndex = codec.dequeueOutputBuffer(info, 10_000)
            when {
                outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> { if (!endOfStream) break }
                outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    videoTrackIndex = muxer_.addTrack(codec.outputFormat)
                    muxer_.start()
                }
                outputIndex >= 0 -> {
                    val buffer = codec.getOutputBuffer(outputIndex) ?: break
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                        info.size = 0
                    }
                    if (info.size > 0 && videoTrackIndex >= 0) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        muxer_.writeSampleData(videoTrackIndex, buffer, info)
                    }
                    codec.releaseOutputBuffer(outputIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
                else -> break
            }
        }
    }

    // MARK: - JPEG Bitmap → YUV420 conversion for MediaCodec input

    private fun bitmapToYuv420(bitmap: Bitmap): ByteArray {
        val w = bitmap.width
        val h = bitmap.height
        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)

        val yuv = ByteArray(w * h * 3 / 2)
        var yIdx = 0
        var uvIdx = w * h

        for (j in 0 until h) {
            for (i in 0 until w) {
                val p = pixels[j * w + i]
                val r = (p shr 16) and 0xFF
                val g = (p shr  8) and 0xFF
                val b =  p         and 0xFF
                val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                yuv[yIdx++] = y.coerceIn(0, 255).toByte()
                if (j % 2 == 0 && i % 2 == 0) {
                    val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                    val v = ((112 * r - 94 * g -  18 * b + 128) shr 8) + 128
                    yuv[uvIdx++] = u.coerceIn(0, 255).toByte()
                    yuv[uvIdx++] = v.coerceIn(0, 255).toByte()
                }
            }
        }
        return yuv
    }

    private fun createOutputFile(): File {
        val ts  = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val dir = context.getExternalFilesDir(Environment.DIRECTORY_MOVIES)
            ?: context.filesDir
        return File(dir, "screen_$ts.mp4")
    }

    override fun onCleared() {
        super.onCleared()
        streamJob?.cancel()
        if (encoderStarted) runCatching { finalizeRecording() }
    }
}
