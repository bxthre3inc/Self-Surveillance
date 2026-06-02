package com.selfsurveillance.viewer.data.di

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.selfsurveillance.viewer.data.api.SurveillanceApi
import com.selfsurveillance.viewer.data.model.ServerConfig
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    private const val PREFS_NAME = "ss_viewer_prefs"
    private const val KEY_HOST   = "server_host"
    private const val KEY_PORT   = "server_port"

    @Provides @Singleton
    fun provideSharedPrefs(@ApplicationContext ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    @Provides @Singleton
    fun provideServerConfig(prefs: SharedPreferences): ServerConfig = ServerConfig(
        host = prefs.getString(KEY_HOST, "192.168.1.100") ?: "192.168.1.100",
        port = prefs.getInt(KEY_PORT, 3000)
    )

    @Provides @Singleton
    fun provideGson(): Gson = Gson()

    @Provides @Singleton
    fun provideOkHttp(): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .addInterceptor(HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        })
        .build()

    @Provides @Singleton
    fun provideRetrofit(client: OkHttpClient, gson: Gson, config: ServerConfig): Retrofit =
        Retrofit.Builder()
            .baseUrl(config.baseUrl)
            .client(client)
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()

    @Provides @Singleton
    fun provideApi(retrofit: Retrofit): SurveillanceApi =
        retrofit.create(SurveillanceApi::class.java)
}
