"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/auth";
import { checkboxValue } from "@/lib/form-values";
import { parseGroupForm, parsePair, parseRoomForm, validatePermission } from "@/lib/room-access-form";
import { createClient } from "@/lib/supabase/server";

function resultUrl(kind: "hiba" | "uzenet", message: string) {
  return `/admin/hozzaferesek?${new URLSearchParams({ [kind]: message }).toString()}`;
}

function safeRpcMessage(error: { code?: string; message?: string }, fallback: string) {
  return ["P0001", "22023", "22004"].includes(error.code ?? "") && (error.message?.length ?? 0) <= 240
    ? error.message! : fallback;
}

async function finish(error: { code?: string; message?: string } | null, success: string, fallback: string) {
  if (error) redirect(resultUrl("hiba", safeRpcMessage(error, fallback)));
  revalidatePath("/admin/hozzaferesek");
  redirect(resultUrl("uzenet", success));
}

export async function saveRoom(formData: FormData) {
  await requireAdmin();
  const parsed = parseRoomForm({
    roomId: String(formData.get("roomId") ?? ""), name: String(formData.get("name") ?? ""),
    displayOrder: String(formData.get("displayOrder") ?? ""),
  });
  if (!parsed.ok) redirect(resultUrl("hiba", parsed.error));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_upsert_room", {
    p_room_id: parsed.value.roomId, p_name: parsed.value.name, p_display_order: parsed.value.displayOrder,
    p_is_training_room: checkboxValue(formData, "isTrainingRoom"),
    p_is_active: checkboxValue(formData, "isActive"), p_correlation_id: crypto.randomUUID(),
  });
  await finish(error, "A helyiség adatai elmentve.", "A helyiség mentése nem sikerült.");
}

export async function saveGroup(formData: FormData) {
  await requireAdmin();
  const parsed = parseGroupForm({ groupId: String(formData.get("groupId") ?? ""), name: String(formData.get("name") ?? "") });
  if (!parsed.ok) redirect(resultUrl("hiba", parsed.error));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_upsert_access_group", {
    p_group_id: parsed.value.groupId, p_name: parsed.value.name,
    p_is_active: checkboxValue(formData, "isActive"), p_correlation_id: crypto.randomUUID(),
  });
  await finish(error, "A hozzáférési csoport elmentve.", "A csoport mentése nem sikerült.");
}

export async function saveUserRoomPermission(formData: FormData) {
  await requireAdmin();
  const pair = parsePair(String(formData.get("userId") ?? ""), String(formData.get("roomId") ?? ""));
  const canBook = checkboxValue(formData, "canBook"); const canRepeat = checkboxValue(formData, "canRepeat");
  const permission = validatePermission(canBook, canRepeat);
  if (!pair.ok) redirect(resultUrl("hiba", pair.error));
  if (!permission.ok) redirect(resultUrl("hiba", permission.error));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_user_room_permission", {
    p_user_id: pair.value.firstId, p_room_id: pair.value.secondId,
    p_can_book: canBook, p_can_repeat: canRepeat, p_correlation_id: crypto.randomUUID(),
  });
  await finish(error, "A közvetlen helyiségjog elmentve.", "A közvetlen helyiségjog mentése nem sikerült.");
}

export async function saveGroupMember(formData: FormData) {
  await requireAdmin();
  const pair = parsePair(String(formData.get("groupId") ?? ""), String(formData.get("userId") ?? ""));
  if (!pair.ok) redirect(resultUrl("hiba", pair.error));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_group_member", {
    p_group_id: pair.value.firstId, p_user_id: pair.value.secondId,
    p_is_member: checkboxValue(formData, "isMember"), p_correlation_id: crypto.randomUUID(),
  });
  await finish(error, "A csoporttagság elmentve.", "A csoporttagság mentése nem sikerült.");
}

export async function saveGroupRoomPermission(formData: FormData) {
  await requireAdmin();
  const pair = parsePair(String(formData.get("groupId") ?? ""), String(formData.get("roomId") ?? ""));
  const canBook = checkboxValue(formData, "canBook"); const canRepeat = checkboxValue(formData, "canRepeat");
  const permission = validatePermission(canBook, canRepeat);
  if (!pair.ok) redirect(resultUrl("hiba", pair.error));
  if (!permission.ok) redirect(resultUrl("hiba", permission.error));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_group_room_permission", {
    p_group_id: pair.value.firstId, p_room_id: pair.value.secondId,
    p_can_book: canBook, p_can_repeat: canRepeat, p_correlation_id: crypto.randomUUID(),
  });
  await finish(error, "A csoport helyiségjoga elmentve.", "A csoport helyiségjogának mentése nem sikerült.");
}
