import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../../../domain/usecases/feedback/gleap/open_gleap_feedback_form.dart';
import 'category/widget.dart';

class GleapFeedbackTile extends StatelessWidget {
  const GleapFeedbackTile({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingLinkTileCategory(
      onTap: () => unawaited(OpenGleapFeedbackForm()()),
      // Deliberately not localized via Phrase.
      text: 'Submit feedback via Gleap',
      icon: FontAwesomeIcons.commentDots,
    );
  }
}
