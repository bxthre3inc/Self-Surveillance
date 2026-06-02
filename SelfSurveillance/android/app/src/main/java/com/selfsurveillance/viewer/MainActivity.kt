package com.selfsurveillance.viewer

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.selfsurveillance.viewer.ui.navigation.NavGraph
import com.selfsurveillance.viewer.ui.theme.SSViewerTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            SSViewerTheme {
                NavGraph()
            }
        }
    }
}
