package com.voipgrid.vialer

import android.app.Activity
import android.app.Application.ActivityLifecycleCallbacks
import android.os.Bundle

class ActivityMonitor : ActivityLifecycleCallbacks {
    private val activities = mutableListOf<Activity>()

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
        activities.add(activity)
    }

    override fun onActivityDestroyed(activity: Activity) {
        activities.remove(activity)
    }

    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityResumed(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}

    /**
     * This must be called on all active activities to properly send the app to the background.
     */
    fun sendAppToBackground() {
        activities.forEach { it.moveTaskToBack(true) }
    }
}