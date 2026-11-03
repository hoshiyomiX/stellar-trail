<script setup>
// explorer UI v5.0.1 — file preview modal: the v4.4 hand-rolled .modal is replaced
// by the REAL miuix-vue Dialog (Task 53 component-layer swap); the preview
// branching (img/pdf/binary/md/json/text) + the 10 s fetch deadline + the
// AbortError message + focus restore are ported verbatim from v4.4 openPreview.
// Task 67 (platform-preview kill, explorer.py v1.10 companion): the /file/
// serving default is now ATTACHMENT — direct URL hits download, foreign inline
// previews die at the source. THIS modal is the only inline consumer: img/pdf
// hrefs carry ?inline=1 (the sole inline path), the binary download + all
// download anchors carry ?dl=1; text branches read via fetch() and never see
// Content-Disposition at all.
import { ref, reactive, onMounted, onBeforeUnmount, nextTick } from 'vue'
import { MiuixDialog, MiuixIconButton } from 'miuix-vue'
import { fetchT, copyPath } from '../explorer.js'
import { fmtSize, fmtDate, esc, iconFor, classFor } from '../util.js'
import { md, hlJSON } from '../preview.js'

const open = ref(false)
const file = ref(null)
const body = reactive({ kind: 'loading', html: '', msg: '', icon: '', cls: '', name: '', href: '', trunc: false })
let lastFocus = null

const BINARY = ['docx', 'pptx', 'xlsx', 'xls', 'doc', 'ppt', 'skill', 'zip', 'tar', 'gz']

// Task 58 hang fix: ALL text-bearing preview branches draw from ONE capped
// source — md()/hlJSON() previously ran on the WHOLE file (a 5 MB worklog-style
// md froze the main thread ~2.9 s at 57k DOM nodes; a 5 MB json ~4.3 s, both
// stress-measured). 200k chars ≈ the existing text-branch cap; the full file
// stays one click away via the download link on the truncation notice.
const PREVIEW_CAP = 200000

function openModal(){ lastFocus = document.activeElement }
function closeModal(){
  open.value = false
  if (lastFocus && lastFocus.focus) lastFocus.focus()
}
async function openPreview(f){
  file.value = f
  const cls = classFor(f)
  body.kind = 'loading'; body.msg = ''; body.html = ''; body.trunc = false
  open.value = true
  openModal()
  await nextTick()
  const e = (f.ext || '').toLowerCase()
  try{
    if (f.type === 'img'){ body.kind = 'img'; body.href = f.href + '?inline=1'; body.name = f.name; return }
    if (e === 'pdf'){ body.kind = 'pdf'; body.href = f.href + '?inline=1'; return }
    if (BINARY.includes(e) || f.type === 'office' || f.type === 'pkg'){
      body.kind = 'binary'; body.icon = iconFor(f); body.cls = cls
      body.name = f.name; body.href = f.href + '?dl=1'
      body.msg = 'Format <b>' + esc((e || f.type).toUpperCase()) + '</b> has no direct browser preview.<br>.skill = skill package (zip) · office = open in the respective application.'
      return
    }
    const t = await (await fetchT(f.href, 10000)).text()
    const src = t.length > PREVIEW_CAP ? t.slice(0, PREVIEW_CAP) : t
    body.trunc = t.length > PREVIEW_CAP
    if (e === 'md'){ body.kind = 'md'; body.html = md(src); return }
    if (e === 'json'){ body.kind = 'json'; body.html = hlJSON(src); return }
    body.kind = 'text'; body.html = esc(src)
  }catch(err){
    body.kind = 'error'
    body.msg = (err && err.name === 'AbortError')
      ? 'preview timed out — the sandbox may be asleep; reopen the preview after it wakes'
      : 'Failed to load the preview: ' + esc(err.message)
  }
}
function onKey(e){ if (e.key === 'Escape' && open.value) closeModal() }
onMounted(() => document.addEventListener('keydown', onKey))
onBeforeUnmount(() => document.removeEventListener('keydown', onKey))
defineExpose({ open: openPreview })
</script>
<template>
  <MiuixDialog :model-value="open" @update:model-value="v => !v && closeModal()" close-on-click-modal
               :title="file ? file.rel : ''" :summary="file ? (fmtSize(file.size) + ' · ' + fmtDate(file.mtime)) : ''">
    <template #default>
      <div class="mhead" v-if="file">
        <span class="micon" :class="'t-' + classFor(file)" id="mIconWrap"><svg class="ic" id="mIcon"><use :href="'#i-' + iconFor(file)"/></svg></span>
        <div class="mnm">
          <div class="nm" id="mName">{{ file.rel }}</div>
          <div class="meta" id="mMeta">{{ fmtSize(file.size) }} · {{ fmtDate(file.mtime) }}</div>
        </div>
        <MiuixIconButton title="Copy the file path on the server" aria-label="Copy the file path on the server" @click="copyPath(file)">
          <svg class="ic"><use href="#i-copy"/></svg>
        </MiuixIconButton>
        <a class="btn" :href="file.href + '?dl=1'" :download="file.name">
          <svg class="ic"><use href="#i-down"/></svg>Download
        </a>
        <MiuixIconButton aria-label="Close preview" @click="closeModal">
          <svg class="ic"><use href="#i-close"/></svg>
        </MiuixIconButton>
      </div>
      <div class="mbody" id="mBody">
        <div v-if="body.trunc && body.kind !== 'loading'" class="truncnote" id="mTrunc">
          <svg class="ic"><use href="#i-info"/></svg>
          Preview truncated — showing the first {{ fmtSize(PREVIEW_CAP) }} of {{ fmtSize(file ? file.size : 0) }}.
          <a :href="file.href + '?dl=1'" :download="file.name">Download the full file</a>
        </div>
        <div v-if="body.kind === 'loading'" class="loadcard"><div class="spinner"></div><p>loading preview…</p></div>
        <img v-else-if="body.kind === 'img'" :src="body.href" :alt="body.name">
        <iframe v-else-if="body.kind === 'pdf'" :src="body.href" title="pdf"></iframe>
        <div v-else-if="body.kind === 'binary'" class="loadcard">
          <div class="ftile" :class="'t-' + body.cls"><svg class="ic"><use :href="'#i-' + body.icon"/></svg></div>
          <p v-html="body.msg"></p>
          <a class="btn" :href="body.href" :download="body.name"><svg class="ic"><use href="#i-down"/></svg>Download {{ body.name }}</a>
        </div>
        <div v-else-if="body.kind === 'md'" class="md" v-html="body.html"></div>
        <pre v-else-if="body.kind === 'json'" v-html="body.html"></pre>
        <pre v-else-if="body.kind === 'text'" v-html="body.html"></pre>
        <div v-else-if="body.kind === 'error'" class="loadcard">
          <div class="ftile" style="background:var(--mx-error-container);color:var(--mx-on-error-container)"><svg class="ic"><use href="#i-warn"/></svg></div>
          <p>{{ body.msg }}</p>
        </div>
      </div>
    </template>
  </MiuixDialog>
</template>
<style scoped>
.truncnote{display:flex;align-items:center;gap:8px;padding:8px 10px;margin-bottom:10px;border-radius:10px;background:var(--mx-surface-variant);color:var(--mx-on-surface-variant);font-size:12px}
.truncnote .ic{width:14px;height:14px;fill:currentColor;flex:none}
.truncnote a{color:var(--mx-primary);font-weight:600;text-decoration:none}
.mhead{display:flex;align-items:center;gap:10px;padding:2px 2px 10px;border-bottom:1px solid var(--mx-divider);margin-bottom:10px}
.mhead .micon{flex:0 0 auto}
.mhead .mnm{flex:1 1 auto;min-width:0}
.mhead .nm{font-weight:600;font-size:14px;line-height:1.25;word-break:break-all}
.mhead .meta{font-size:11px;color:var(--mx-text-2);margin-top:2px}
.mhead .btn{white-space:nowrap}
.mbody{max-height:60vh;overflow:auto}
.mbody img{max-width:100%;border-radius:8px}
.mbody iframe{width:100%;height:60vh;border:0;border-radius:8px;background:#fff}
.mbody pre{white-space:pre-wrap;word-break:break-all;font-family:var(--mx-mono);font-size:12px;line-height:1.5;color:var(--mx-on-card)}
</style>
