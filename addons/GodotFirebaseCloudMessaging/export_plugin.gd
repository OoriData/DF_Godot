@tool
extends EditorPlugin

# A class member to hold the editor export plugin during its lifecycle.
var export_plugin: AndroidExportPlugin

func _enter_tree():
	# Initialization of the plugin goes here.
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree():
	# Clean-up of the plugin goes here.
	remove_export_plugin(export_plugin)
	export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	var _plugin_name = "GodotFirebaseCloudMessaging"

	func _supports_platform(platform):
		if platform is EditorExportPlatformAndroid:
			return true
		return false

	func _get_android_libraries(platform, debug):
		if debug:
			return PackedStringArray(["res://addons/" + _plugin_name + "/bin/release/" + _plugin_name + "-release.aar"])
		else:
			return PackedStringArray(["res://addons/" + _plugin_name + "/bin/release/" + _plugin_name + "-release.aar"])

	func _get_android_dependencies(platform, debug):
		# Firebase Cloud Messaging and its core dependency
		return PackedStringArray([
			"com.google.firebase:firebase-messaging:24.1.0",
			"com.google.firebase:firebase-common:21.0.0"
		])

	func _get_android_manifest_application_element_contents(platform, debug):
		# Inject the FCM service declaration into the merged AndroidManifest.xml
		return """
		<service android:name="com.ooridata.godotfcm.FCMService"
			android:exported="false">
			<intent-filter>
				<action android:name="com.google.firebase.MESSAGING_EVENT"/>
			</intent-filter>
		</service>
		"""

	func _get_android_manifest_element_contents(platform, debug):
		# Ensure POST_NOTIFICATIONS permission is declared (belt-and-suspenders)
		return '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />'

	func _get_name():
		return _plugin_name
