import { useState } from "react";
import { Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View, type KeyboardTypeOptions } from "react-native";
import { supportedCurrencies } from "../format";
import { transactionCategories } from "../types";
import { useTheme } from "../theme";
import { hairline } from "./Glass";
import { Icon } from "./Icon";

export function FormField({
  label,
  value,
  onChangeText,
  placeholder,
  keyboardType,
  autoCapitalize = "sentences",
  secureTextEntry,
  multiline,
  autoFocus,
}: {
  label?: string;
  value: string;
  onChangeText: (text: string) => void;
  placeholder?: string;
  keyboardType?: KeyboardTypeOptions;
  autoCapitalize?: "none" | "sentences" | "words";
  secureTextEntry?: boolean;
  multiline?: boolean;
  autoFocus?: boolean;
}) {
  const palette = useTheme();
  return (
    <View style={styles.field}>
      {label ? <Text style={[styles.fieldLabel, { color: palette.label }]}>{label}</Text> : null}
      <TextInput
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={palette.tertiaryLabel}
        keyboardType={keyboardType}
        autoCapitalize={autoCapitalize}
        autoCorrect={false}
        secureTextEntry={secureTextEntry}
        multiline={multiline}
        autoFocus={autoFocus}
        style={[styles.input, label ? { textAlign: "right" } : null, { color: palette.label }]}
      />
    </View>
  );
}

export function AmountHeader({
  title,
  amount,
  onChangeAmount,
  currency,
  onChangeCurrency,
  tone,
  currencyLocked,
  autoFocus = false,
}: {
  title: string;
  amount: string;
  onChangeAmount: (value: string) => void;
  currency: string;
  onChangeCurrency?: (currency: string) => void;
  tone?: string;
  currencyLocked?: boolean;
  autoFocus?: boolean;
}) {
  const palette = useTheme();
  const [picking, setPicking] = useState(false);
  return (
    <View style={styles.amountBlock}>
      <Text style={[styles.amountTitle, { color: palette.secondaryLabel }]}>{title}</Text>
      <TextInput
        value={amount}
        onChangeText={(text) => onChangeAmount(text.replace(/[^0-9.,+-]/g, ""))}
        placeholder="0"
        placeholderTextColor={palette.tertiaryLabel}
        keyboardType="decimal-pad"
        autoFocus={autoFocus}
        style={[styles.amountInput, { color: tone ?? palette.label }]}
      />
      {currencyLocked || !onChangeCurrency ? (
        <View style={[styles.currencyPill, { backgroundColor: palette.fill }]}>
          <Text style={{ color: palette.label, fontSize: 15, fontWeight: "600" }}>{currency}</Text>
        </View>
      ) : (
        <Pressable
          onPress={() => setPicking(true)}
          style={[styles.currencyPill, { backgroundColor: palette.fill, flexDirection: "row", gap: 5 }]}
        >
          <Text style={{ color: palette.label, fontSize: 15, fontWeight: "600" }}>{currency}</Text>
          <Icon name="chevronDown" size={10} color={palette.secondaryLabel} />
        </Pressable>
      )}
      <CurrencyModal
        visible={picking}
        selected={currency}
        onSelect={(code) => {
          onChangeCurrency?.(code);
          setPicking(false);
        }}
        onClose={() => setPicking(false)}
      />
    </View>
  );
}

export function CurrencyRow({ currency, onChange }: { currency: string; onChange: (code: string) => void }) {
  const palette = useTheme();
  const [picking, setPicking] = useState(false);
  const name = supportedCurrencies.find((item) => item.code === currency)?.name ?? currency;
  return (
    <>
      <Pressable onPress={() => setPicking(true)} style={styles.field}>
        <Text style={[styles.fieldLabel, { color: palette.label }]}>Currency</Text>
        <View style={{ flex: 1 }} />
        <Text style={{ color: palette.secondaryLabel, fontSize: 17 }}>{`${currency} — ${name}`}</Text>
        <Icon name="chevronRight" size={12} color={palette.tertiaryLabel} />
      </Pressable>
      <CurrencyModal
        visible={picking}
        selected={currency}
        onSelect={(code) => {
          onChange(code);
          setPicking(false);
        }}
        onClose={() => setPicking(false)}
      />
    </>
  );
}

export function CurrencyModal({
  visible,
  selected,
  onSelect,
  onClose,
}: {
  visible: boolean;
  selected: string;
  onSelect: (code: string) => void;
  onClose: () => void;
}) {
  const palette = useTheme();
  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet" onRequestClose={onClose}>
      <View style={{ flex: 1, backgroundColor: palette.background }}>
        <View style={styles.modalHeader}>
          <Text style={[styles.modalTitle, { color: palette.label }]}>Currency</Text>
          <Pressable onPress={onClose}>
            <Text style={{ color: palette.blue, fontSize: 17 }}>Done</Text>
          </Pressable>
        </View>
        <ScrollView contentContainerStyle={{ paddingBottom: 30 }}>
          {supportedCurrencies.map((option) => (
            <Pressable
              key={option.code}
              onPress={() => onSelect(option.code)}
              style={[styles.currencyRow, { borderColor: palette.separator }]}
            >
              <Text style={{ color: palette.label, fontSize: 17 }}>{`${option.code} — ${option.name}`}</Text>
              {selected === option.code ? <Icon name="checkmark" size={16} color={palette.blue} /> : null}
            </Pressable>
          ))}
        </ScrollView>
      </View>
    </Modal>
  );
}

export function CategoryPicker({
  value,
  onChange,
  label = "Category",
}: {
  value: string;
  onChange: (category: string) => void;
  label?: string;
}) {
  const palette = useTheme();
  const [visible, setVisible] = useState(false);
  const [custom, setCustom] = useState("");
  return (
    <>
      <Pressable onPress={() => setVisible(true)} style={styles.field}>
        <Text style={[styles.fieldLabel, { color: palette.label }]}>{label}</Text>
        <View style={{ flex: 1 }} />
        <Text style={{ color: palette.secondaryLabel, fontSize: 17 }}>{value || "Uncategorized"}</Text>
        <Icon name="chevronRight" size={12} color={palette.tertiaryLabel} />
      </Pressable>
      <Modal visible={visible} animationType="slide" presentationStyle="pageSheet" onRequestClose={() => setVisible(false)}>
        <View style={{ flex: 1, backgroundColor: palette.background }}>
          <View style={styles.modalHeader}>
            <Text style={[styles.modalTitle, { color: palette.label }]}>Category</Text>
            <Pressable onPress={() => setVisible(false)}>
              <Text style={{ color: palette.blue, fontSize: 17 }}>Done</Text>
            </Pressable>
          </View>
          <ScrollView>
            {transactionCategories.map((category) => (
              <Pressable
                key={category}
                onPress={() => {
                  onChange(category);
                  setVisible(false);
                }}
                style={[styles.currencyRow, { borderColor: palette.separator }]}
              >
                <Text style={{ color: palette.label, fontSize: 17 }}>{category}</Text>
                {value === category ? <Icon name="checkmark" size={16} color={palette.blue} /> : null}
              </Pressable>
            ))}
          </ScrollView>
          <View style={[styles.customRow, { borderColor: palette.separator }]}>
            <TextInput
              value={custom}
              onChangeText={setCustom}
              placeholder="Custom category"
              placeholderTextColor={palette.tertiaryLabel}
              style={[styles.input, { color: palette.label, flex: 1 }]}
            />
            <Pressable
              disabled={!custom.trim()}
              onPress={() => {
                onChange(custom.trim());
                setCustom("");
                setVisible(false);
              }}
            >
              <Text style={{ color: custom.trim() ? palette.blue : palette.tertiaryLabel, fontSize: 17, fontWeight: "600" }}>Use</Text>
            </Pressable>
          </View>
        </View>
      </Modal>
    </>
  );
}


const styles = StyleSheet.create({
  field: { flexDirection: "row", alignItems: "center", gap: 10, paddingHorizontal: 16, paddingVertical: 12, minHeight: 50 },
  fieldLabel: { fontSize: 17 },
  input: { flex: 1, fontSize: 17, paddingVertical: 2 },
  amountBlock: { alignItems: "center", gap: 10, paddingVertical: 18 },
  amountTitle: { fontSize: 15 },
  amountInput: { fontSize: 46, fontWeight: "600", textAlign: "center", minWidth: 160, fontVariant: ["tabular-nums"] },
  currencyPill: { paddingHorizontal: 13, paddingVertical: 6, borderRadius: 999, alignItems: "center" },
  modalHeader: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 20,
    paddingVertical: 16,
  },
  modalTitle: { fontSize: 20, fontWeight: "700" },
  currencyRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 20,
    paddingVertical: 15,
    borderTopWidth: hairline,
  },
  customRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderTopWidth: hairline,
  },
});
