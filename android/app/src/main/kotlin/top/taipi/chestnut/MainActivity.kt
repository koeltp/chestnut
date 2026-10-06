package top.taipi.chestnut

// 必须继承 FlutterFragmentActivity：local_auth 的 Android 生物识别
// 依赖 FragmentActivity（BiometricPrompt），FlutterActivity 会直接报错
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
