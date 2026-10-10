import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../services/people_api.dart';
import '../../utils/translations.dart';
import '../people/person_card.dart';
import '../people/people_routes.dart';
import 'section_title.dart';

/// STAFF on the media detail page: a row of the credited people with their
/// roles, each opening their staff page. Hidden when there's nobody to show.
class StaffSection extends StatelessWidget {
  const StaffSection({super.key, required this.edges});

  /// The detail query's `staff { edges { role node { id name { full }
  /// image { medium } } } }` edges; malformed ones are skipped and people
  /// credited twice are shown once with both roles.
  final List<dynamic> edges;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final credits = StaffCredit.listFromEdges(edges);
    if (credits.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: DetailSectionTitle(tr('staff', lang).toUpperCase()),
        ),
        SizedBox(
          height: PersonCard.rowHeight(),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: credits.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (context, i) {
              final credit = credits[i];
              return PersonCard(
                name: credit.staff.name,
                imageUrl: credit.staff.imageUrl,
                subtitle: credit.roles.join(', '),
                onTap: () => openStaff(context, credit.staff),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
      ],
    );
  }
}
