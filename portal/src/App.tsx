import { useState } from "react"
import { GlowCard } from "./components/GlowCard"

const S3 = "https://levpn-clients.s3.amazonaws.com/clients"

const nodes = [
  { region: "us", label: "United States", location: "Virginia", latency: "120ms", glowColor: "blue" as const },
  { region: "eu", label: "Europe", location: "Ireland", latency: "20ms", glowColor: "purple" as const },
  { region: "asia", label: "Asia", location: "Singapore", latency: "180ms", glowColor: "green" as const },
  { region: "sa", label: "South America", location: "Sao Paulo", latency: "200ms", glowColor: "orange" as const },
]

type OS = "macos" | "windows"

export default function App() {
  const [os, setOs] = useState<OS>("macos")

  const url = (region: string) => os === "windows" ? S3+"/levpn-"+region+"-windows.exe" : S3+"/levpn-"+region+"-macos"

  const btn = (active: boolean): React.CSSProperties => ({
    padding: "8px 24px", borderRadius: 8, fontSize: 14, fontWeight: 500, cursor: "pointer", border: "none",
    background: active ? "white" : "transparent", color: active ? "black" : "rgba(255,255,255,0.5)",
  })

  const stepsWin = [
    "Download levpn-{region}-windows.exe for your region",
    "Open cmd.exe : Win+R then type cmd then Enter",
    "Run : cd Downloads && levpn-us-windows.exe — keep this window open",
    "Install FoxyProxy extension in your browser",
    "FoxyProxy > Add proxy > SOCKS5 > 127.0.0.1:1080 > Save > Enable",
  ]

  const stepsMac = [
    "Download levpn-{region}-macos for your region",
    "Open Terminal",
    "Run : chmod +x ~/Downloads/levpn-us-macos",
    "Run : xattr -cr ~/Downloads/levpn-us-macos",
    "Run : ~/Downloads/levpn-us-macos — keep this window open",
    "Install FoxyProxy extension in your browser",
    "FoxyProxy > Add proxy > SOCKS5 > 127.0.0.1:1080 > Save > Enable",
  ]

  const steps = os === "windows" ? stepsWin : stepsMac

  return (
    <div style={{minHeight:"100vh",background:"#0a0a0a",color:"white",fontFamily:"system-ui,sans-serif"}}>
      <header style={{borderBottom:"1px solid rgba(255,255,255,0.1)",padding:"20px 32px",display:"flex",justifyContent:"space-between",alignItems:"center"}}>
        <span style={{fontWeight:600,fontSize:18}}>levpn</span>
        <span style={{color:"rgba(255,255,255,0.4)",fontSize:14}}>aguenonnvpn.com</span>
      </header>
      <section style={{textAlign:"center",padding:"80px 32px 40px"}}>
        <h1 style={{fontSize:48,fontWeight:700,marginBottom:16,letterSpacing:"-0.02em"}}>Your private tunnel, everywhere</h1>
        <p style={{color:"rgba(255,255,255,0.5)",fontSize:18}}>WebSocket tunnel over TLS. 4 regions. No complex setup.</p>
      </section>
      <div style={{display:"flex",justifyContent:"center",marginBottom:48}}>
        <div style={{display:"flex",gap:4,background:"rgba(255,255,255,0.05)",borderRadius:12,padding:4,border:"1px solid rgba(255,255,255,0.1)"}}>
          <button onClick={() => setOs("macos")} style={btn(os==="macos")}>macOS</button>
          <button onClick={() => setOs("windows")} style={btn(os==="windows")}>Windows</button>
        </div>
      </div>
      <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(220px,1fr))",gap:24,maxWidth:1100,margin:"0 auto",padding:"0 32px 80px"}}>
        {nodes.map((n) => (
          <GlowCard key={n.region} glowColor={n.glowColor}>
            <div style={{display:"flex",flexDirection:"column",gap:16,height:"100%"}}>
              <div>
                <h2 style={{fontSize:20,fontWeight:600}}>{n.label}</h2>
                <p style={{color:"rgba(255,255,255,0.4)",fontSize:14,marginTop:4}}>{n.location}</p>
              </div>
              <div style={{display:"flex",alignItems:"center",gap:8,marginTop:"auto"}}>
                <div style={{width:8,height:8,borderRadius:"50%",background:"#4ade80"}}></div>
                <span style={{color:"rgba(255,255,255,0.4)",fontSize:12}}>Online · {n.latency}</span>
              </div>
              <a href={url(n.region)} download style={{display:"block",textAlign:"center",padding:10,borderRadius:8,background:"rgba(255,255,255,0.1)",border:"1px solid rgba(255,255,255,0.1)",fontSize:14,fontWeight:500,color:"white",textDecoration:"none"}}>Download</a>
            </div>
          </GlowCard>
        ))}
      </section>
      <section style={{maxWidth:640,margin:"0 auto",padding:"0 32px 80px"}}>
        <h3 style={{fontSize:16,fontWeight:600,marginBottom:24,textAlign:"center",color:"rgba(255,255,255,0.6)"}}>Setup guide</h3>
        {steps.map((text, i) => (
          <div key={i} style={{display:"flex",gap:16,padding:16,borderRadius:12,background:"rgba(255,255,255,0.05)",border:"1px solid rgba(255,255,255,0.1)",marginBottom:12}}>
            <span style={{color:"rgba(255,255,255,0.2)",fontFamily:"monospace",fontWeight:700,fontSize:14,minWidth:24}}>0{i+1}</span>
            <span style={{color:"rgba(255,255,255,0.6)",fontSize:14}}>{text}</span>
          </div>
        ))}
      </section>
    </div>
  )
}