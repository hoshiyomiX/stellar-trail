// explorer UI v5.0 — theme via the real miuix-vue theme system (Task 53).
// Default: follow the system (owner answer Q7 "Auto sistem") until the user
// picks manually — the pick persists in localStorage, exactly the v4.4
// behavior ("adaptive: follow the system until the user picks manually (persisted)").
// miuix-vue manages .m-theme-dark on <html>; we mirror data-theme for the
// carried v4.4 CSS block (:root[data-theme="dark"|"light"]).
import { setThemeMode, useTheme } from 'miuix-vue'
import { watch } from 'vue'

export function bootTheme(onTheme){
  let saved=null;
  try{saved=localStorage.getItem("miuix-theme")}catch(_){}
  setThemeMode((saved==="dark"||saved==="light")?saved:"system");
  const { theme }=useTheme();
  watch(theme,t=>{
    document.documentElement.dataset.theme=t;
    onTheme&&onTheme(t);
  },{immediate:true});
}
export function toggleTheme(){
  const next=document.documentElement.dataset.theme==="dark"?"light":"dark";
  try{localStorage.setItem("miuix-theme",next);
      localStorage.removeItem("md3-theme")}catch(e){}
  setThemeMode(next);
}
