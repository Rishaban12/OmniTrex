# R8 keep rules for release builds.
#
# Some plugins are called from Dart through JNI (jnigen bindings). R8 can't
# see those calls and strips the methods, which crashed release builds at
# startup: NoSuchMethodError SharedPreferencesApiRegistrar.getAll(...).

# shared_preferences / path_provider (JNI-backed on Android).
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
# package:jni runtime used by those bindings.
-keep class com.github.dart_lang.jni.** { *; }

# flutter_local_notifications stores scheduled notifications with Gson,
# which needs generic type info and its model classes intact.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Our own receivers / services / widget (SMS, notification listener, DoList widget).
-keep class com.dailybudget.daily_budget.** { *; }
