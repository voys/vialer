import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:vialer/presentation/resources/localizations.dart';
import 'package:vialer/presentation/resources/theme.dart';
import 'package:vialer/presentation/shared/widgets/stylized_button.dart';
import 'package:vialer/presentation/util/context_extensions.dart';

import '../../controllers/contacts/cubit.dart';

class RestrictedPermissionWarning extends StatelessWidget {
  const RestrictedPermissionWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = context.msg.main.colltacts.contacts.limitedPermission;

    return Column(
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: context.colors.primaryLighter,
              radius: 16,
              child: Icon(
                Icons.info_outline,
                color: context.colors.primary,
                size: 18,
              ),
            ),
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.title,
                    style: TextStyle(
                      color: context.colors.userAvailabilityOffline,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    strings.description(context.brand.appName),
                    style: TextStyle(
                      color: context.colors.grey5,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Gap(10),
        StylizedButton.outline(
          colored: true,
          margin: EdgeInsets.zero,
          onPressed: () =>
              context.read<ContactsCubit>().requestMoreRestrictedContacts(),
          child: Text(strings.button),
        ),
      ],
    );
  }
}
