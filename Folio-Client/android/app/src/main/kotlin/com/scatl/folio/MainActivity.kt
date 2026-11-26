package com.scatl.folio

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var sensorManager: SensorManager? = null
    private var sink: EventChannel.EventSink? = null

    private val listener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            sink?.success(listOf(event.values[0].toDouble(), event.values[1].toDouble()))
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "com.scatl.folio/orientation").setMethodCallHandler { call, result ->
            if (call.method == "rotationLocked") {
                val locked = Settings.System.getInt(
                    contentResolver,
                    Settings.System.ACCELEROMETER_ROTATION,
                    1,
                ) == 0
                result.success(locked)
            } else {
                result.notImplemented()
            }
        }
        EventChannel(messenger, "com.scatl.folio/orientation_gravity").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sink = events
                    val manager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
                    sensorManager = manager
                    val sensor = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                    if (sensor == null) {
                        events.error("unavailable", "没有加速度传感器", null)
                        return
                    }
                    manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
                }

                override fun onCancel(arguments: Any?) {
                    sensorManager?.unregisterListener(listener)
                    sensorManager = null
                    sink = null
                }
            },
        )
    }
}
