import React, { useRef, useState } from "react";
import {
  Image,
  ScrollView,
  StyleSheet,
  Text,
  TVFocusGuideView,
  View,
} from "react-native";
import { Detail, Progress, resumeTarget } from "../../domain/model";
import { Button, palette } from "../components";
import { EPISODE_GROUP_SIZE } from "./layout";

export function DetailTV({
  detail,
  progress,
  favorite,
  onFavorite,
  onPlay,
  restoreEpisode,
}: {
  detail: Detail;
  progress?: Progress;
  favorite: boolean;
  onFavorite: () => void;
  onPlay: (index: number, position: number) => void;
  restoreEpisode?: string;
}) {
  const current = detail.episodes.findIndex(
    (e) => e.id === (restoreEpisode || progress?.episodeId)
  );
  const [group, setGroup] = useState(
    Math.floor(Math.max(0, current) / EPISODE_GROUP_SIZE)
  );
  const [expanded, setExpanded] = useState(false);
  const scroll = useRef<ScrollView>(null);
  const episodeTop = useRef(0);
  const target = resumeTarget(detail, progress);
  return (
    <ScrollView
      ref={scroll}
      contentContainerStyle={{ padding: 6, paddingBottom: 20 }}
    >
      <View style={s.hero}>
        <Image source={{ uri: detail.cover }} style={s.cover} />
        <View style={{ flex: 1, gap: 8 }}>
          <Text style={s.title} numberOfLines={2}>
            {detail.title}
          </Text>
          <Text style={s.muted} numberOfLines={1}>
            {detail.badge} · {detail.tags}
          </Text>
          {detail.celebrities.length > 0 && (
            <Text style={s.cast} numberOfLines={2}>
              {detail.celebrities
                .map((c) =>
                  c.role && c.role !== c.name
                    ? `${c.name}（饰 ${c.role}）`
                    : c.name
                )
                .join(" · ")}
            </Text>
          )}
          <Text style={s.description} numberOfLines={expanded ? undefined : 2}>
            {detail.description}
          </Text>
          <View style={s.row}>
            <Button
              label={progress ? "继续观看" : "开始播放"}
              primary
              preferred={!restoreEpisode}
              onFocus={() =>
                scroll.current?.scrollTo({ y: 0, animated: false })
              }
              onPress={() => onPlay(target.index, target.position)}
            />
            <Button
              label={favorite ? "已收藏 ✓" : "＋ 收藏"}
              onPress={onFavorite}
            />
            <Button
              label={expanded ? "收起简介" : "完整简介"}
              onPress={() => setExpanded(!expanded)}
            />
          </View>
        </View>
      </View>
      <View
        onLayout={(e) => {
          episodeTop.current = e.nativeEvent.layout.y;
        }}
      >
        <Text style={s.section}>选集 · {detail.episodes.length} 集</Text>
        <TVFocusGuideView trapFocusLeft trapFocusRight style={[s.row, { paddingHorizontal: 10 }]}>
          {Array.from(
            { length: Math.ceil(detail.episodes.length / EPISODE_GROUP_SIZE) },
            (_, i) => (
              <Button
                key={i}
                label={`${i * EPISODE_GROUP_SIZE + 1}–${Math.min(
                  (i + 1) * EPISODE_GROUP_SIZE,
                  detail.episodes.length
                )}`}
                primary={group === i}
                onPress={() => setGroup(i)}
                onFocus={() =>
                  scroll.current?.scrollTo({
                    y: episodeTop.current,
                    animated: false,
                  })
                }
              />
            )
          )}
        </TVFocusGuideView>
        <TVFocusGuideView autoFocus style={[s.row, { marginTop: 16, paddingHorizontal: 10 }]}>
          {detail.episodes
            .slice(group * EPISODE_GROUP_SIZE, (group + 1) * EPISODE_GROUP_SIZE)
            .map((e, i) => (
              <Button
                key={e.id}
                label={String(e.number)}
                style={{ width: 98 }}
                primary={progress?.episodeId === e.id}
                preferred={restoreEpisode === e.id}
                onPress={() => onPlay(group * EPISODE_GROUP_SIZE + i, 0)}
                onFocus={() =>
                  scroll.current?.scrollTo({
                    y: episodeTop.current,
                    animated: false,
                  })
                }
              />
            ))}
        </TVFocusGuideView>
      </View>
    </ScrollView>
  );
}
const s = StyleSheet.create({
  hero: { flexDirection: "row", gap: 30, marginBottom: 24, paddingHorizontal: 10 },
  cover: { width: 160, height: 224, borderRadius: 16 },
  title: {
    fontSize: 34,
    lineHeight: 42,
    fontWeight: "700",
    color: palette.text,
  },
  muted: { fontSize: 17, color: palette.muted },
  cast: { fontSize: 17, lineHeight: 24, color: palette.muted },
  description: { fontSize: 19, lineHeight: 28, color: palette.muted },
  row: { flexDirection: "row", flexWrap: "wrap", gap: 14 },
  section: {
    fontSize: 26,
    fontWeight: "700",
    color: palette.text,
    marginBottom: 14,
  },
});
