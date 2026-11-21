<script setup>
// explorer UI v5.1.0 — SelectBar (Task 84, owner order "Add feature Task File
// Manager: delete files dan multi selection action option"; batch set
// owner-confirmed: delete + zip-download + move + copy).
// A fixed bottom bar while selection mode is active: the count, the four
// batch actions, and Cancel. Delete = PERMANENT with a miuix confirmation
// dialog (owner answer); zip = server-side .zip that starts downloading and
// also lands in the file list; move/copy = destination dialog (existing
// folders from GET /api/folders + a new-folder name, both validated again
// server-side). Feedback flows through the Task-69 sr-only announcer — no
// popups, no snackbar platform (the dialogs are the task file manager's own,
// same as the preview modal).
import { ref, computed } from 'vue'
import { MiuixDialog } from 'miuix-vue'
import { S, SEL, ui, exitSel, actDelete, actZip, actTransfer, fetchFolders } from '../explorer.js'

const busy = ref(false)
const dlg = ref(null)          // 'delete' | 'dest' | null
const destMode = ref('move')   // 'move' | 'copy'
const folders = ref([])
const destPick = ref('')       // '' = root, or a rel folder path
const newDir = ref('')
const destErr = ref('')

const names = computed(() => [...SEL].map(k => (k.includes('/') ? k.split('/').slice(1).pop() : k)))
const preview5 = computed(() => names.value.slice(0, 5))
const more = computed(() => Math.max(0, names.value.length - 5))

function fail(msg){ ui.announce = ''; setTimeout(() => { ui.announce = msg }, 50) }

async function openDest(mode){
  destMode.value = mode; dlg.value = 'dest'; destErr.value = ''; newDir.value = ''; destPick.value = ''
  try { folders.value = await fetchFolders() } catch (e) { folders.value = [] }
}
function chosenDest(){
  const nd = newDir.value.trim()
  if (nd) {
    if (!/^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$/.test(nd)) {
      destErr.value = 'Folder name: start with a letter/digit; then letters, digits, space . _ - only'
      return null
    }
    return nd
  }
  return destPick.value
}
async function runDelete(){
  busy.value = true
  try { await actDelete(SEL); dlg.value = null; exitSel() }
  catch (e) { fail('Delete failed: ' + e.message) }
  busy.value = false
}
async function runZip(){
  busy.value = true
  try { await actZip(SEL); exitSel() }
  catch (e) { fail('Zip failed: ' + e.message) }
  busy.value = false
}
async function runDest(){
  const dest = chosenDest()
  if (dest === null) return
  busy.value = true
  try { await actTransfer(destMode.value, SEL, dest); dlg.value = null; exitSel() }
  catch (e) { destErr.value = e.message }
  busy.value = false
}
</script>
<template>
  <div v-if="S.selMode" class="selbar" role="toolbar" aria-label="Batch actions for the selection">
    <span class="scount"><b>{{ SEL.size }}</b> selected</span>
    <div class="sactions">
      <button class="sbtn" :disabled="busy" title="Delete the selection (permanent)" :aria-label="'Delete ' + SEL.size + ' selected item(s)'" @click="dlg = 'delete'"><svg class="ic"><use href="#i-delete"/></svg><span>Delete</span></button>
      <button class="sbtn" :disabled="busy" title="Download the selection as one .zip" :aria-label="'Zip and download ' + SEL.size + ' selected item(s)'" @click="runZip()"><svg class="ic"><use href="#i-down"/></svg><span>Zip</span></button>
      <button class="sbtn" :disabled="busy" title="Move the selection into a folder" :aria-label="'Move ' + SEL.size + ' selected item(s)'" @click="openDest('move')"><svg class="ic"><use href="#i-move"/></svg><span>Move</span></button>
      <button class="sbtn" :disabled="busy" title="Copy the selection into a folder" :aria-label="'Copy ' + SEL.size + ' selected item(s)'" @click="openDest('copy')"><svg class="ic"><use href="#i-copy"/></svg><span>Copy</span></button>
    </div>
    <button class="scancel" :disabled="busy" title="Leave selection mode" aria-label="Cancel the selection" @click="exitSel()"><svg class="ic"><use href="#i-close"/></svg></button>
  </div>

  <!-- delete confirm (owner: permanent + miuix confirmation dialog) -->
  <MiuixDialog :model-value="dlg === 'delete'" @update:model-value="v => !v && (dlg = null)"
               title="Delete selection?" :summary="SEL.size + ' item(s) — permanent'" close-on-click-modal>
    <div class="ddlg">
      <ul class="dnames">
        <li v-for="n in preview5" :key="n">{{ n }}</li>
      </ul>
      <div v-if="more" class="dmore">…and {{ more }} more</div>
      <div class="dwarn"><svg class="ic"><use href="#i-warn"/></svg>Permanent — deleted files cannot be recovered. Operational files are refused by the server.</div>
      <div class="dbtns">
        <button class="btn" :disabled="busy" @click="dlg = null">Cancel</button>
        <button class="btn danger" :disabled="busy" @click="runDelete()"><svg class="ic"><use href="#i-delete"/></svg>Delete {{ SEL.size }}</button>
      </div>
    </div>
  </MiuixDialog>

  <!-- move/copy destination picker -->
  <MiuixDialog :model-value="dlg === 'dest'" @update:model-value="v => !v && (dlg = null)"
               :title="(destMode === 'move' ? 'Move' : 'Copy') + ' selection'" :summary="SEL.size + ' item(s) — choose the destination'" close-on-click-modal>
    <div class="ddlg">
      <div class="destlist" role="radiogroup" aria-label="Destination folder">
        <button class="destitem" :class="{ on: !destPick && !newDir }" role="radio"
                :aria-checked="(!destPick && !newDir) ? 'true' : 'false'"
                @click="destPick = ''; newDir = ''">
          <svg class="ic"><use href="#i-logo"/></svg>.zscripts/ (root)
        </button>
        <button v-for="fd in folders" :key="fd" class="destitem" :class="{ on: destPick === fd && !newDir }"
                role="radio" :aria-checked="(destPick === fd && !newDir) ? 'true' : 'false'"
                @click="destPick = fd; newDir = ''">
          <svg class="ic"><use href="#i-logo"/></svg>{{ fd }}
        </button>
      </div>
      <label class="newdir"><svg class="ic"><use href="#i-newdir"/></svg><input v-model="newDir" placeholder="…or a new folder name" maxlength="64"></label>
      <div v-if="destErr" class="derr">{{ destErr }}</div>
      <div class="dbtns">
        <button class="btn" :disabled="busy" @click="dlg = null">Cancel</button>
        <button class="btn" :disabled="busy" @click="runDest()"><svg class="ic"><use :href="(destMode === 'move') ? '#i-move' : '#i-copy'"/></svg>{{ destMode === 'move' ? 'Move' : 'Copy' }} {{ SEL.size }}</button>
      </div>
    </div>
  </MiuixDialog>
</template>
