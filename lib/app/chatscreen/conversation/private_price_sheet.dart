import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_models.dart';
import '../../component/c_button.dart';
import '../../component/c_text.dart';
import '../../component/keyboard_inset.dart';
import '../../component/pressable.dart';
import '../../listingflow/profile/profile_sheets.dart';
import '../helper/chat_pricing.dart';

/// A host prices a private photo: quick picks inside the admin's range or
/// an own amount, and what they earn from it. Rupees, or null when backed
/// out.
Future<double?> askPrivatePhotoPrice(
  BuildContext context,
  ChatPrivatePhotoRules rules,
) => showProfileSheet<double>(
  context,
  (_) => KeyboardInset(child: _PriceSheet(rules: rules)),
  name: 'chat_private_price_sheet',
);

class _PriceSheet extends HookWidget {
  const _PriceSheet({required this.rules});

  final ChatPrivatePhotoRules rules;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final picks = useMemoized(() => ChatPricing.privatePicks(rules), [rules]);
    final price = useState<double?>(
      picks.isEmpty ? rules.minPrice : picks[picks.length > 1 ? 1 : 0],
    );
    final custom = useTextEditingController();
    final valid = ChatPricing.privatePriceAllowed(price.value, rules);
    final earn = valid
        ? ChatPricing.privateSharePaise(price.value!, rules.hostSharePercent)
        : 0;
    final range = {
      'min': ChatPricing.money(rules.minPrice),
      'max': ChatPricing.money(rules.maxPrice),
    };

    return SheetCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(
            icon: LucideIcons.lockKeyhole,
            iconColor: BrandColors.lime,
            title: 'chat:private.price_title',
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.ms, 14.ms, 20.ms, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CText(
                  'chat:private.price_body',
                  size: 12.5,
                  weight: FontWeight.w500,
                  color: c.textMuted,
                ),
                SizedBox(height: 14.ms),
                Wrap(
                  spacing: 8.ms,
                  runSpacing: 8.ms,
                  children: [
                    for (final p in picks)
                      _Pick(
                        label: ChatPricing.money(p),
                        selected: price.value == p && custom.text.isEmpty,
                        onTap: () {
                          custom.clear();
                          price.value = p;
                        },
                      ),
                  ],
                ),
                SizedBox(height: 12.ms),
                MediaQuery.withNoTextScaling(
                  child: TextField(
                    key: const ValueKey('chat-private-price'),
                    controller: custom,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,6}(\.\d{0,2})?'),
                      ),
                    ],
                    style: TextStyle(color: c.text, fontSize: 15.ms),
                    cursorColor: c.accent,
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      hintText: context.t('chat:private.price_custom'),
                      helperText: context.t(
                        'chat:private.price_range',
                        variables: range,
                      ),
                      enabledBorder: _border(c.border),
                      focusedBorder: _border(c.accent),
                    ),
                    onChanged: (v) => price.value = double.tryParse(v.trim()),
                  ),
                ),
                SizedBox(height: 10.ms),
                if (valid)
                  CText(
                    'chat:private.price_earn',
                    variables: {
                      'earn': ChatPricing.moneyPaise(earn),
                      'percent': '${rules.hostSharePercent}',
                    },
                    size: 13,
                    weight: FontWeight.w700,
                    color: StatusColors.success,
                  ),
                SizedBox(height: 14.ms),
                CButton(
                  key: const ValueKey('chat-private-send'),
                  title: valid
                      ? 'chat:private.price_send'
                      : 'chat:private.price_set',
                  titleVariables: valid
                      ? {'price': ChatPricing.money(price.value!)}
                      : null,
                  showArrow: false,
                  disabled: !valid,
                  onPressed: valid
                      ? () => Navigator.of(context).pop(price.value)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14.ms),
    borderSide: BorderSide(color: color),
  );
}

class _Pick extends StatelessWidget {
  const _Pick({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onPressed: onTap,
      child: Container(
        height: 36.ms,
        padding: EdgeInsets.symmetric(horizontal: 14.ms),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.accentA(0.15) : AppColors.transparent,
          borderRadius: BorderRadius.circular(12.ms),
          border: Border.all(color: selected ? c.accent : c.border),
        ),
        child: CText.raw(
          label,
          size: 13,
          weight: FontWeight.w800,
          color: selected ? c.accent : c.text,
        ),
      ),
    );
  }
}
