import { test } from "node:test";
import assert from "node:assert/strict";
import { normalizeCelebrities } from "../server/provider.mjs";

test("missing or empty input yields empty list", () => {
  assert.deepEqual(normalizeCelebrities(undefined), []);
  assert.deepEqual(normalizeCelebrities(null), []);
  assert.deepEqual(normalizeCelebrities([]), []);
});

test("array of celebrity objects is normalized to stable fields", () => {
  assert.deepEqual(
    normalizeCelebrities([
      { id: "a1", name: "张三", role: "饰演 叶秋", avatar: "https://x/a.jpg" },
      { actor_id: "a2", actor_name: "李四", actor_role: "反派", head_url: "https://x/b.jpg" },
    ]),
    [
      { id: "a1", name: "张三", role: "叶秋", avatar: "https://x/a.jpg" },
      { id: "a2", name: "李四", role: "反派", avatar: "https://x/b.jpg" },
    ]
  );
});

test("real upstream shape (nickname/sub_title/celebrity_id) is normalized", () => {
  assert.deepEqual(
    normalizeCelebrities([
      {
        nickname: "孟娜",
        avatar: "https://x/a.jpg",
        sub_title: "饰 顾娇",
        celebrity_id: "7377325995637871897",
      },
      {
        nickname: "刘润铭",
        avatar: "https://x/b.jpg",
        sub_title: "饰演 男主",
        celebrity_id: "7377325995637871898",
      },
    ]),
    [
      {
        id: "7377325995637871897",
        name: "孟娜",
        role: "顾娇",
        avatar: "https://x/a.jpg",
      },
      {
        id: "7377325995637871898",
        name: "刘润铭",
        role: "男主",
        avatar: "https://x/b.jpg",
      },
    ]
  );
});

test("string entries become name-only celebrities", () => {
  assert.deepEqual(normalizeCelebrities(["王五", "赵六"]), [
    { id: "", name: "王五", role: "", avatar: "" },
    { id: "", name: "赵六", role: "", avatar: "" },
  ]);
});

test("wrapper objects with list/actors keys are unwrapped", () => {
  assert.deepEqual(
    normalizeCelebrities({ actors: [{ name: "钱七", role: "主角" }] }),
    [{ id: "", name: "钱七", role: "主角", avatar: "" }]
  );
  assert.deepEqual(
    normalizeCelebrities({ list: [{ name: "孙八" }] }),
    [{ id: "", name: "孙八", role: "", avatar: "" }]
  );
});

test("empty-name entries are dropped, escaped URLs are cleaned", () => {
  assert.deepEqual(
    normalizeCelebrities([{ name: "" }, { name: "周九", avatar: "https:\\/\\/x\\/c.jpg" }]),
    [{ id: "", name: "周九", role: "", avatar: "https://x/c.jpg" }]
  );
});
