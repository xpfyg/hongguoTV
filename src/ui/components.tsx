import React, { forwardRef, useRef, useState } from "react";
import {
  ActivityIndicator,
  Animated,
  Image,
  Pressable,
  StyleSheet,
  Text,
  View,
  ViewStyle,
} from "react-native";
import { Series } from "../domain/model";

/** tvOS 26 风格暗色体系：纯黑底 + 玻璃半透明面板 + 细边框高光 + 品牌橙强调 */
export const palette = {
  bg: "#000000",
  panel: "#1A1A1F",
  glass: "#FFFFFF12",
  glassStrong: "#FFFFFF1F",
  glassBorder: "#FFFFFF24",
  muted: "#9B9BA8",
  text: "#FFFFFF",
  accent: "#FF6B4A",
  border: "#26262C",
  black: "#000000",
};

const focusScale = 1.12;
const focusShadow = {
  shadowColor: "#000000",
  shadowOpacity: 0.55,
  shadowRadius: 22,
  shadowOffset: { width: 0, height: 10 },
  elevation: 12,
} as const;

/** tvOS 标准聚焦反馈：放大 + 阴影 + 反色/提亮 */
function useFocusScale() {
  const scale = useRef(new Animated.Value(1)).current;
  const [focused, setFocused] = useState(false);
  const grow = () =>
    Animated.spring(scale, {
      toValue: focusScale,
      useNativeDriver: true,
      speed: 22,
      bounciness: 4,
    }).start();
  const shrink = () =>
    Animated.spring(scale, {
      toValue: 1,
      useNativeDriver: true,
      speed: 22,
      bounciness: 4,
    }).start();
  return {
    focused,
    focus: () => {
      setFocused(true);
      grow();
    },
    blur: () => {
      setFocused(false);
      shrink();
    },
    style: { transform: [{ scale }] },
  };
}

export const Button = forwardRef<
  View,
  {
    label: string;
    onPress: () => void;
    primary?: boolean;
    preferred?: boolean;
    disabled?: boolean;
    style?: ViewStyle;
    onFocus?: () => void;
    onBlur?: () => void;
    testID?: string;
    focusable?: boolean;
  }
>(function Button(
  {
    label,
    onPress,
    primary = false,
    preferred = false,
    disabled = false,
    style,
    onFocus,
    onBlur,
    testID,
    focusable,
  },
  ref
) {
  const preferredUsed = useRef(false);
  const fx = useFocusScale();
  return (
    <Animated.View style={fx.style}>
      <Pressable
        ref={ref}
        testID={testID}
        focusable={focusable}
        accessibilityRole="button"
        accessibilityLabel={label}
        hasTVPreferredFocus={preferred && !preferredUsed.current}
        disabled={disabled}
        onFocus={() => {
          preferredUsed.current = true;
          fx.focus();
          onFocus?.();
        }}
        onBlur={() => {
          fx.blur();
          onBlur?.();
        }}
        onPress={onPress}
        style={[
          s.button,
          primary && s.primary,
          fx.focused && s.buttonFocused,
          disabled && { opacity: 0.3 },
          fx.focused && primary && s.buttonFocused,
          style,
        ]}
      >
        <Text
          style={[
            s.buttonText,
            fx.focused && s.buttonTextFocused,
            primary && s.buttonTextPrimary,
          ]}
        >
          {label}
        </Text>
      </Pressable>
    </Animated.View>
  );
});

export const Card = forwardRef<
  View,
  {
    item: Series;
    width: number;
    coverHeight: number;
    titleHeight: number;
    onPress: () => void;
    onFocus: () => void;
    preferred?: boolean;
  }
>(function Card(
  { item, width, coverHeight, titleHeight, onPress, onFocus, preferred },
  ref
) {
  const preferredUsed = useRef(false);
  const [broken, setBroken] = useState(false);
  const fx = useFocusScale();
  return (
    <Animated.View style={fx.style}>
      <Pressable
        ref={ref}
        accessibilityRole="button"
        accessibilityLabel={`${item.title}，${item.badge}`}
        hasTVPreferredFocus={preferred && !preferredUsed.current}
        onFocus={() => {
          preferredUsed.current = true;
          fx.focus();
          onFocus();
        }}
        onBlur={() => fx.blur()}
        onPress={onPress}
        style={[s.card, { width }, fx.focused && focusShadow]}
      >
        <View style={[s.cover, { height: coverHeight }]}>
          {item.cover && !broken ? (
            <Image
              source={{ uri: item.cover }}
              resizeMode="cover"
              onError={() => setBroken(true)}
              style={StyleSheet.absoluteFill}
            />
          ) : (
            <View style={s.placeholderBox}>
              <Text style={s.placeholder}>红果</Text>
            </View>
          )}
          <View style={s.badge}>
            <Text numberOfLines={1} style={s.badgeText}>
              {item.badge || "短剧"}
            </Text>
          </View>
        </View>
        <Text numberOfLines={2} style={[s.title, { height: titleHeight }]}>
          {item.title}
        </Text>
      </Pressable>
    </Animated.View>
  );
});

export function Notice({
  message,
  busy = false,
  retry,
}: {
  message: string;
  busy?: boolean;
  retry?: () => void;
}) {
  return (
    <View style={s.notice}>
      {busy && <ActivityIndicator color={palette.accent} size="large" />}
      <Text style={s.noticeText}>{message}</Text>
      {retry && <Button label="重试" onPress={retry} primary preferred />}
    </View>
  );
}

const s = StyleSheet.create({
  button: {
    backgroundColor: palette.glass,
    borderWidth: 1,
    borderColor: palette.glassBorder,
    borderRadius: 18,
    paddingHorizontal: 22,
    paddingVertical: 13,
    alignItems: "center",
    justifyContent: "center",
    minHeight: 56,
  },
  primary: { backgroundColor: palette.accent, borderColor: "transparent" },
  buttonFocused: {
    backgroundColor: "#FFFFFF",
    borderColor: "#FFFFFF",
  },
  buttonText: { color: palette.text, fontSize: 18, fontWeight: "600" },
  buttonTextFocused: { color: palette.black },
  buttonTextPrimary: { color: "#FFFFFF" },
  card: {
    margin: 8,
    padding: 5,
    borderRadius: 18,
  },
  cover: {
    borderRadius: 13,
    overflow: "hidden",
    backgroundColor: palette.panel,
    alignItems: "center",
    justifyContent: "center",
  },
  placeholderBox: { flex: 1, alignItems: "center", justifyContent: "center" },
  placeholder: { color: "#8A4A52", fontSize: 34, fontWeight: "800" },
  badge: {
    position: "absolute",
    bottom: 0,
    right: 0,
    left: 0,
    backgroundColor: "#000000B0",
    paddingVertical: 7,
    paddingHorizontal: 10,
  },
  badgeText: { color: "#FFFFFF", fontSize: 15, fontWeight: "600" },
  title: {
    color: palette.text,
    fontSize: 20,
    lineHeight: 27,
    fontWeight: "600",
    marginTop: 12,
    paddingHorizontal: 2,
  },
  notice: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: 36,
    gap: 26,
  },
  noticeText: {
    color: palette.muted,
    fontSize: 21,
    textAlign: "center",
    maxWidth: 640,
    lineHeight: 32,
  },
});
