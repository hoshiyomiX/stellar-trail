// explorer UI v5.0 — entry. Styles: the real miuix-vue stylesheet + the
// verbatim-carried v4.4 explorer skin (palette from compose-miuix-ui/miuix
// Colors.kt, D10 compact typography) + the app entry.
import 'miuix-vue/style.css'
import './style/explorer.css'
import { createApp } from 'vue'
import App from './App.vue'

createApp(App).mount('#app')
