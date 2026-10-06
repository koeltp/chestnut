import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import 'privacy_policy_page.dart';

/// 首次启动隐私同意页：未同意前不构建主界面，任何第三方 SDK 均不初始化、
/// 不发起网络请求。"暂不同意"直接退出应用，符合应用商店审核要求。
class PrivacyConsentPage extends StatelessWidget {
  const PrivacyConsentPage({required this.onAgree, super.key});

  /// 用户点击"同意并继续"后的回调（持久化同意状态、初始化合规 SDK）
  final VoidCallback onAgree;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 系统返回键直接退出，防止绕过同意进入应用
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Image.asset('assets/images/logo.png', width: 84, height: 84),
                const SizedBox(height: 20),
                const Text(
                  '欢迎使用栗子记账',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  '栗子记账是一款无广告、无账号的本地记账工具。'
                  '你的账目、备注与位置等数据全部保存在本机，不会上传到任何服务器。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.8,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                // 隐私政策入口：同意前必须保证可完整查看
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PrivacyPolicyPage(),
                    ),
                  ),
                  child: const Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.8,
                        color: AppColors.textSecondary,
                      ),
                      children: [
                        TextSpan(text: '继续即表示你已阅读并同意'),
                        TextSpan(
                          text: '《隐私政策》',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: onAgree,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      '同意并继续',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: () => SystemNavigator.pop(),
                    child: const Text(
                      '暂不同意，退出应用',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
