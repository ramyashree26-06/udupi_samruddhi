package com.udupisamruddhi.hotel_billing

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "hotel/usb_printer"
    private val permAction = "com.udupisamruddhi.hotel_billing.USB_PERMISSION"

    private fun usb(): UsbManager = getSystemService(Context.USB_SERVICE) as UsbManager

    // finds the printer interface + its "write" endpoint
    private fun findOut(d: UsbDevice): Pair<UsbInterface, UsbEndpoint>? {
        var fallback: Pair<UsbInterface, UsbEndpoint>? = null
        for (i in 0 until d.interfaceCount) {
            val intf = d.getInterface(i)
            for (e in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(e)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                    ep.direction == UsbConstants.USB_DIR_OUT) {
                    if (intf.interfaceClass == UsbConstants.USB_CLASS_PRINTER) return Pair(intf, ep)
                    if (fallback == null) fallback = Pair(intf, ep)
                }
            }
        }
        return fallback
    }

    private fun printerDevices(): List<UsbDevice> =
        usb().deviceList.values.filter { d ->
            (0 until d.interfaceCount).any { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_PRINTER }
        }

    private fun nameOf(d: UsbDevice): String {
        return try {
            d.productName ?: "USB printer ${d.vendorId}:${d.productId}"
        } catch (e: Exception) {
            "USB printer ${d.vendorId}:${d.productId}"
        }
    }

    private fun writeTo(d: UsbDevice, data: ByteArray, result: MethodChannel.Result) {
        Thread {
            var msg: String? = null
            try {
                val pair = findOut(d)
                val conn = usb().openDevice(d)
                if (pair == null || conn == null) {
                    msg = "Could not open the USB printer."
                } else {
                    conn.claimInterface(pair.first, true)
                    var off = 0
                    while (off < data.size) {
                        val n = minOf(4096, data.size - off)
                        val r = conn.bulkTransfer(pair.second, data, off, n, 5000)
                        if (r < 0) {
                            msg = "The printer did not accept the data. Check paper and power."
                            break
                        }
                        off += n
                    }
                    conn.releaseInterface(pair.first)
                    conn.close()
                }
            } catch (e: Exception) {
                msg = "USB print problem: ${e.message}"
            }
            runOnUiThread {
                if (msg == null) result.success(true) else result.error("USB", msg, null)
            }
        }.start()
    }

    private fun printBytes(data: ByteArray, result: MethodChannel.Result) {
        val list = printerDevices()
        if (list.isEmpty()) {
            result.error("USB", "No USB printer found. Check the OTG cable and that the printer is ON.", null)
            return
        }
        val dev = list[0]
        val mgr = usb()
        if (mgr.hasPermission(dev)) {
            writeTo(dev, data, result)
            return
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) {
                try { unregisterReceiver(this) } catch (e: Exception) {}
                if (i.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                    writeTo(dev, data, result)
                } else {
                    result.error("USB", "USB permission was not allowed. Tap Allow and try again.", null)
                }
            }
        }
        val filter = IntentFilter(permAction)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        val pi = PendingIntent.getBroadcast(this, 0, Intent(permAction).setPackage(packageName), flags)
        mgr.requestPermission(dev, pi)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "list" -> result.success(printerDevices().map { mapOf("name" to nameOf(it)) })
                "print" -> {
                    val data = call.argument<ByteArray>("bytes")
                    if (data == null) result.error("USB", "Nothing to print.", null) else printBytes(data, result)
                }
                else -> result.notImplemented()
            }
        }
    }
}
