// explorer UI v5.0 — markdown mini-renderer + JSON highlighter, ported verbatim from UI v4.4
import { esc } from './util.js'

export function md(src){const lines=src.split("\n");const out=[];let inCode=false,cb=[],inList=false;
  const inline=t=>esc(t).replace(/\*\*(.+?)\*\*/g,"<b>$1</b>").replace(/\*(.+?)\*/g,"<i>$1</i>")
    .replace(/`([^`]+)`/g,"<code>$1</code>").replace(/\[([^\]]+)\]\(([^)]+)\)/g,'<a href="$2" target="_blank" rel="noopener">$1</a>');
  for(const l of lines){
    if(l.trim().startsWith("```")){if(inCode){out.push("<pre>"+esc(cb.join("\n"))+"</pre>");cb=[];inCode=false}else{if(inList){out.push("</ul>");inList=false}inCode=true}continue}
    if(inCode){cb.push(l);continue}
    const h=l.match(/^(#{1,4})\s+(.*)/);
    if(h){if(inList){out.push("</ul>");inList=false}const n=h[1].length;out.push(`<h${n}>`+inline(h[2])+`</h${n}>`);continue}
    const li=l.match(/^\s*[-*]\s+(.*)/);
    if(li){if(!inList){out.push("<ul>");inList=true}out.push("<li>"+inline(li[1])+"</li>");continue}
    if(inList){out.push("</ul>");inList=false}
    if(l.trim()==="")continue;
    if(l.trim().startsWith(">")){out.push("<blockquote>"+inline(l.replace(/^\s*>\s?/,""))+"</blockquote>");continue}
    out.push("<p>"+inline(l)+"</p>")}
  if(inList)out.push("</ul>");if(inCode)out.push("<pre>"+esc(cb.join("\n"))+"</pre>");
  return out.join("\n")}

export function hlJSON(src){try{src=JSON.stringify(JSON.parse(src),null,2)}catch(e){}
  return esc(src)
    .replace(/("(?:[^"\\]|\\.)*")(\s*:)?/g,(m,s,c)=>c?`<span class="k">${s}</span>${c}`:`<span class="s2">${s}</span>`)
    .replace(/\b(-?\d+\.?\d*)\b/g,'<span class="n">$1</span>')
    .replace(/\b(true|false|null)\b/g,'<span class="b2">$1</span>')}
