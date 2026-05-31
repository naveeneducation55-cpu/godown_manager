// ─────────────────────────────────────────────────────────────────────────────
// feedback_screen.dart — v2.7.3
//
// Simple feedback form for beta testing.
// Controlled by app_config.feedback_enabled — toggle without APK update.
//
// Flow:
//   Open → check hasSubmittedToday()
//     Already submitted → show AlreadyDoneView
//     Not submitted     → show form
//   Submit → validate → server check → insert → show ThankYouView
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../common_widgets.dart';
import '../../providers/app_data_provider.dart';
import '../../services/feedback_service.dart';
import '../../services/remote_config_service.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

enum _FeedbackView { loading, form, alreadyDone, thankYou }

class _FeedbackScreenState extends State<FeedbackScreen> {

  final _ctrl        = TextEditingController();
  final _scrollCtrl  = ScrollController();

  _FeedbackView _view      = _FeedbackView.loading;
  bool          _submitting = false;
  String?       _errorMsg;

  int get _minChars => RemoteConfigService.instance.feedbackMinChars;
  int get _maxChars => RemoteConfigService.instance.feedbackMaxChars;
  int get _charCount => _ctrl.text.length;
  bool get _canSubmit =>
      _charCount >= _minChars &&
      _charCount <= _maxChars &&
      !_submitting;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
    _checkAlreadySubmitted();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Check submitted today ──────────────────────────────────────────────────
  Future<void> _checkAlreadySubmitted() async {
    final done = await FeedbackService.instance.hasSubmittedToday();
    if (!mounted) return;
    setState(() => _view = done
        ? _FeedbackView.alreadyDone
        : _FeedbackView.form);
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() { _submitting = true; _errorMsg = null; });

    final data       = context.read<AppDataProvider>();
    final shopId     = data.shopId;
    final staffId    = data.currentStaff?.id ?? '';
    final appVersion = '2.7.3';

    final result = await FeedbackService.instance.submit(
      shopId:     shopId,
      staffId:    staffId,
      message:    _ctrl.text,
      appVersion: appVersion,
      minChars:   _minChars,
      maxChars:   _maxChars,
    );

    if (!mounted) return;

    switch (result) {
      case FeedbackResult.success:
        setState(() => _view = _FeedbackView.thankYou);
      case FeedbackResult.alreadySubmitted:
        setState(() {
          _view      = _FeedbackView.alreadyDone;
          _submitting = false;
        });
      case FeedbackResult.tooShort:
        setState(() {
          _errorMsg   = 'Please write at least $_minChars characters.';
          _submitting = false;
        });
      case FeedbackResult.tooLong:
        setState(() {
          _errorMsg   = 'Feedback must be under $_maxChars characters.';
          _submitting = false;
        });
      case FeedbackResult.empty:
        setState(() {
          _errorMsg   = 'Please enter your feedback before submitting.';
          _submitting = false;
        });
      case FeedbackResult.networkError:
        setState(() {
          _errorMsg   = 'No internet connection. Please try again.';
          _submitting = false;
        });
      case FeedbackResult.serverError:
        setState(() {
          _errorMsg   = 'Something went wrong. Please try again later.';
          _submitting = false;
        });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor:          t.surface,
        leading:                  const AppBackButton(),
        title: Text(
          'Feedback',
          style: AppFonts.heading(color: t.text).copyWith(fontSize: 16),
        ),
        elevation:              0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: switch (_view) {
            _FeedbackView.loading     => _buildLoading(t),
            _FeedbackView.form        => _buildForm(t),
            _FeedbackView.alreadyDone => _buildAlreadyDone(t),
            _FeedbackView.thankYou    => _buildThankYou(t),
          },
        ),
      ),
    );
  }

  // ── Loading ────────────────────────────────────────────────────────────────
  Widget _buildLoading(AppThemeExtension t) => Center(
    key: const ValueKey('loading'),
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: t.primary,
    ),
  );

  // ── Form ───────────────────────────────────────────────────────────────────
  Widget _buildForm(AppThemeExtension t) {
    final isNearLimit = _charCount >= (_maxChars * 0.95).floor();
    final isOverLimit = _charCount > _maxChars;

    return SingleChildScrollView(
      key:        const ValueKey('form'),
      controller: _scrollCtrl,
      padding:    const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const SizedBox(height: AppSpacing.sm),

          // ── Header ────────────────────────────────────────────────────────
          Text(
            'Help us improve',
            style: AppFonts.heading(color: t.text),
          ),
          const SizedBox(height: 6),
          Text(
            'Your feedback goes directly to the development team '
            'and helps us make the app better for everyone.',
            style: AppFonts.body(color: t.text2),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── Text area ─────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color:        t.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              border: Border.all(
                color: isOverLimit
                    ? t.error
                    : _ctrl.text.isNotEmpty
                        ? t.primary.withValues(alpha: 0.5)
                        : t.border,
                width: _ctrl.text.isNotEmpty ? 1.5 : 0.8,
              ),
            ),
            child: TextField(
              controller:  _ctrl,
              maxLines:    8,
              minLines:    6,
              style:       AppFonts.body(color: t.text),
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'What worked well? What needs improvement? '
                          'Any issues you faced?',
                hintStyle:       AppFonts.body(color: t.text3),
                border:          InputBorder.none,
                enabledBorder:   InputBorder.none,
                focusedBorder:   InputBorder.none,
                contentPadding:  const EdgeInsets.all(AppSpacing.md),
              ),
            ),
          ),

          // ── Character counter ─────────────────────────────────────────────
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Min chars hint
              if (_charCount < _minChars && _charCount > 0)
                Text(
                  'Minimum $_minChars characters',
                  style: AppFonts.label(color: t.text3),
                )
              else
                const SizedBox.shrink(),
              // Counter
              Text(
                '$_charCount / $_maxChars',
                style: AppFonts.label(
                  color: isOverLimit
                      ? t.error
                      : isNearLimit
                          ? t.warnFg
                          : t.text3,
                ),
              ),
            ],
          ),

          // ── Error message ──────────────────────────────────────────────────
          if (_errorMsg != null) ...[ 
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical:   AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color:        t.errorBg,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, size: 15, color: t.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMsg!,
                    style: AppFonts.label(color: t.error),
                  ),
                ),
              ]),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          // ── Submit button ──────────────────────────────────────────────────
          SizedBox(
            width:  double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _canSubmit ? t.primary : t.border,
                foregroundColor: Colors.white,
                elevation:       0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
                textStyle: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize:   AppTypeScale.md,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: _submitting
                  ? SizedBox(
                      width:  18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    )
                  : const Text('Submit Feedback'),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── Confidentiality note ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color:        t.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border:       Border.all(color: t.border, width: 0.8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 14, color: t.text3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your feedback is confidential and visible only '
                    'to the app team. It cannot be seen by other '
                    'staff or shop owners.',
                    style: AppFonts.label(color: t.text3),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  // ── Already submitted today ────────────────────────────────────────────────
  Widget _buildAlreadyDone(AppThemeExtension t) => Center(
    key: const ValueKey('already'),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width:  64,
            height: 64,
            decoration: BoxDecoration(
              color:  t.successBg,
              shape:  BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size:  32,
              color: t.success,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Already Submitted',
            style: AppFonts.heading(color: t.text),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'You have already shared your feedback today.\n'
            'You can submit again tomorrow.',
            style: AppFonts.body(color: t.text2),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Go Back',
                  style: AppFonts.body(color: t.text)),
            ),
          ),
        ],
      ),
    ),
  );

  // ── Thank you ──────────────────────────────────────────────────────────────
  Widget _buildThankYou(AppThemeExtension t) => Center(
    key: const ValueKey('thankyou'),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          // Icon
          Container(
            width:  72,
            height: 72,
            decoration: BoxDecoration(
              color:  t.successBg,
              shape:  BoxShape.circle,
            ),
            child: Icon(
              Icons.favorite_rounded,
              size:  34,
              color: t.success,
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          Text(
            'Thank You!',
            style: AppFonts.heading(color: t.text).copyWith(
              fontSize: AppTypeScale.xxl,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppSpacing.sm),

          Text(
            'Your feedback has been recorded.',
            style: AppFonts.body(color: t.text),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppSpacing.sm),

          Text(
            'We read every response and use it to make the app '
            'better for you and your team.',
            style: AppFonts.body(color: t.text2),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppSpacing.xl),

          SizedBox(
            width:  double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: Colors.white,
                elevation:       0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
              ),
              child: Text(
                'Done',
                style: AppFonts.body(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
