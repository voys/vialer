import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vialer/presentation/resources/localizations.dart';

import '../../../../../data/models/colltacts/shared_contacts/shared_contact.dart';
import '../../controllers/shared_contact_form/cubit.dart';
import '../../widgets/shared_contact_form/widget.dart';

class AddSharedContactPage extends StatelessWidget {
  const AddSharedContactPage({
    required this.onSave,
    this.prefill,
    super.key,
  });

  final VoidCallback onSave;
  final SharedContact? prefill;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SharedContactFormCubit>(
      create: (_) => SharedContactFormCubit(),
      child: SharedContactForm(
        title: context.msg.main.contacts.list.addSharedContact.title,
        onSave: onSave,
        prefill: prefill,
      ),
    );
  }
}
