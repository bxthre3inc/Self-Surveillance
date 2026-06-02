package com.selfsurveillance.viewer.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Stream
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.selfsurveillance.viewer.ui.screens.DashboardScreen
import com.selfsurveillance.viewer.ui.screens.LiveFeedScreen
import com.selfsurveillance.viewer.ui.screens.LogBrowserScreen
import com.selfsurveillance.viewer.ui.screens.ScreenMirrorScreen

sealed class Screen(val route: String, val label: String) {
    object Dashboard    : Screen("dashboard",    "Dashboard")
    object LiveFeed     : Screen("live",          "Live")
    object LogBrowser   : Screen("logs",          "Logs")
    object ScreenMirror : Screen("screen",        "Screen")
}

private val tabs = listOf(Screen.Dashboard, Screen.LiveFeed, Screen.LogBrowser, Screen.ScreenMirror)
private val tabIcons = mapOf(
    Screen.Dashboard.route    to Icons.Filled.GridView,
    Screen.LiveFeed.route     to Icons.Filled.Stream,
    Screen.LogBrowser.route   to Icons.Filled.List,
    Screen.ScreenMirror.route to Icons.Filled.Tv
)

@Composable
fun NavGraph() {
    val navController = rememberNavController()

    Scaffold(
        bottomBar = {
            NavigationBar {
                val navBackStackEntry by navController.currentBackStackEntryAsState()
                val currentDest = navBackStackEntry?.destination
                tabs.forEach { screen ->
                    NavigationBarItem(
                        icon  = { Icon(tabIcons[screen.route]!!, contentDescription = screen.label) },
                        label = { Text(screen.label) },
                        selected = currentDest?.hierarchy?.any { it.route == screen.route } == true,
                        onClick = {
                            navController.navigate(screen.route) {
                                popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                launchSingleTop = true
                                restoreState    = true
                            }
                        }
                    )
                }
            }
        }
    ) { innerPadding ->
        NavHost(navController, startDestination = Screen.Dashboard.route,
                Modifier.padding(innerPadding)) {
            composable(Screen.Dashboard.route)    { DashboardScreen() }
            composable(Screen.LiveFeed.route)     { LiveFeedScreen() }
            composable(Screen.LogBrowser.route)   { LogBrowserScreen() }
            composable(Screen.ScreenMirror.route) { ScreenMirrorScreen() }
        }
    }
}
