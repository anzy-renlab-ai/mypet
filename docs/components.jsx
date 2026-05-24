/* mypet — main app components */

// Animated APNG paths
const CATS = {
  idle: 'assets/cats/idle.apng',
  sleepy: 'assets/cats/sleepy.apng',
  sleeping: 'assets/cats/sleeping.apng',
  dozing: 'assets/cats/dozing.apng',
  hungry: 'assets/cats/hungry.apng',
  eating: 'assets/cats/eating.apng',
  petting: 'assets/cats/petting.apng',
  purring: 'assets/cats/purring.apng',
  peekRight: 'assets/cats/peekRight.apng',
  clingTop: 'assets/cats/clingTop.apng',
};

// Still PNG posters — drastically cheaper than running 10 APNGs at once.
// Used as default; gallery cards swap to APNG on hover via <PosterCat />.
const STILLS = {
  idle: 'uploads/cat-idle-still.png',
  sleepy: 'uploads/cat-sleepy-still.png',
  sleeping: 'uploads/cat-sleeping-still.png',
  dozing: 'uploads/cat-dozing-still.png',
  hungry: 'uploads/cat-hungry-still.png',
  eating: 'uploads/cat-eating-still.png',
  petting: 'uploads/cat-petting-still.png',
  purring: 'uploads/cat-purring-still.png',
  peekRight: 'uploads/cat-peekRight-still.png',
  clingTop: 'uploads/cat-clingTop-still.png',
};

// Render a still poster; swap to the APNG while the user hovers. Keeps
// page-load decode work down from "10 simultaneous APNGs" to "0 until you
// interact". Pass `alwaysAnimate` for the hero where the motion is the
// whole point.
function PosterCat({ stateKey, alt = '', className = '', alwaysAnimate = false, ...rest }) {
  const [hot, setHot] = React.useState(alwaysAnimate);
  const src = (hot || alwaysAnimate) ? CATS[stateKey] : STILLS[stateKey];
  return (
    <img
      loading="lazy"
      decoding="async"
      src={src}
      alt={alt}
      className={className}
      onMouseEnter={() => setHot(true)}
      onMouseLeave={() => !alwaysAnimate && setHot(false)}
      {...rest}
    />
  );
}

// ---------- Sparkle SVG ----------
function Sparkle({ size = 32, color = '#FFB3C1', className = '' }) {
  return (
    <svg className={className} width={size} height={size} viewBox="0 0 32 32" fill="none">
      <path d="M16 2 L18 14 L30 16 L18 18 L16 30 L14 18 L2 16 L14 14 Z" fill={color} stroke="#2A2018" strokeWidth="2" strokeLinejoin="round"/>
    </svg>
  );
}

// ---------- GitHub star badge ----------
// Fetches the live stargazer count from the GitHub public API and falls
// back to "—" while loading / on error.
const REPO_URL = 'https://github.com/anzy-renlab-ai/mypet';
const KOFI_URL = 'https://ko-fi.com/alvinanziyan';
// The primary install path: paste this into Claude Code and it installs +
// launches mypet for you. (mypet is built for CC users — it feeds on your
// Claude Code tokens, so this is the natural way in.)
const INSTALL_PROMPT = 'Install mypet — a cute 3D desktop kitten that lives in my screen corner and feeds on Claude Code tokens. Run `brew install --cask anzy-renlab-ai/tap/mypet`, then launch the mypet app. Repo: github.com/anzy-renlab-ai/mypet';
function GitHubStarBadge() {
  const [count, setCount] = React.useState(null);
  React.useEffect(() => {
    let cancelled = false;
    fetch('https://api.github.com/repos/anzy-renlab-ai/mypet')
      .then(r => r.ok ? r.json() : Promise.reject(r.status))
      .then(d => { if (!cancelled) setCount(d.stargazers_count); })
      .catch(() => { /* keep null — show "—" */ });
    return () => { cancelled = true; };
  }, []);
  const formatted = count == null
    ? '—'
    : (count >= 1000 ? (count / 1000).toFixed(1) + 'k' : String(count));
  return (
    <a href={REPO_URL} target="_blank" rel="noopener" className="nav-star" title="Star us on GitHub">
      <span className="star-icon">★</span>
      <span className="star-label">Give us a star</span>
      <span className="star-count">{formatted}</span>
    </a>
  );
}

// ---------- Nav ----------
function Nav() {
  return (
    <nav className="nav">
      <div className="nav-logo">
        <span className="dot"></span>
        mypet
      </div>
      <div className="nav-links">
        <a href="#moods">Moods</a>
        <a href="#features">Features</a>
        <a href="#how">How it works</a>
        <a href="#love">Love wall</a>
        <a href="#faq">FAQ</a>
      </div>
      <div className="nav-cta">
        <GitHubStarBadge />

        <button className="nav-pill" onClick={() => document.getElementById('download').scrollIntoView({behavior:'smooth', block:'center'})}>
          Get mypet — free
        </button>
      </div>
    </nav>
  );
}

// ---------- Hero ----------
function Hero({ onHeartBurst }) {
  const stageRef = React.useRef(null);
  const catRef = React.useRef(null);

  // Cat eyes follow mouse — done via tiny translate
  React.useEffect(() => {
    function onMove(e) {
      if (!stageRef.current || !catRef.current) return;
      const r = stageRef.current.getBoundingClientRect();
      const cx = r.left + r.width / 2;
      const cy = r.top + r.height / 2;
      const dx = (e.clientX - cx) / window.innerWidth;
      const dy = (e.clientY - cy) / window.innerHeight;
      catRef.current.style.setProperty('--mx', `${dx * 14}px`);
      catRef.current.style.setProperty('--my', `${dy * 8}px`);
    }
    window.addEventListener('mousemove', onMove);
    return () => window.removeEventListener('mousemove', onMove);
  }, []);

  function handleDownload(e) {
    onHeartBurst(e.clientX, e.clientY);
  }

  return (
    <section className="hero" id="download">
      <div className="hero-grid">
        <div className="hero-copy">
          <span className="hero-eyebrow">
            <span className="live-dot"></span>
            v0.1 · open source · macOS 13+
          </span>
          <h1 className="hero-title">
            A tiny <span className="accent">kitty</span><br />
            who lives on your<br />
            screen<span className="tail">.</span>
          </h1>
          <p className="hero-sub">
            mypet drops a fluffy 3D kitten onto your dock corner. Double-click
            her to spend one <span className="accent">Claude Code</span> call —
            she chomps the token and bubbles back a tip, a prompt, or a punny verse.
            Zero CPU when ignored. Stays quiet, then shows up when you need
            a smile.
          </p>
          <div className="hero-cta">
            <button
              className="btn-primary"
              onClick={(e) => {
                navigator.clipboard.writeText(INSTALL_PROMPT);
                handleDownload && handleDownload(e);
                const b = e.currentTarget.querySelector('.cta-label');
                if (b) { const o = b.textContent; b.textContent = '已复制 ✓ 粘贴给 Claude Code'; setTimeout(() => b.textContent = o, 1800); }
              }}
            >
              <span className="cta-label">Copy the install prompt</span>
              <span className="os-tag">paste into Claude Code · macOS 13+</span>
            </button>
            <a className="btn-ghost"
              href={KOFI_URL}
              target="_blank"
              rel="noopener">
              <span>☕</span> Buy me a ko-fi
            </a>
          </div>
          <pre className="install-prompt"><code>{INSTALL_PROMPT}</code></pre>
          <p className="hero-meta">
            <span>Built for <span className="accent">Claude Code</span> users — she eats your CC tokens.</span><br/>
            <span style={{opacity:0.7}}>No Claude Code yet? Get it first → </span>
            <a href="https://docs.anthropic.com/claude-code" target="_blank" rel="noopener">claude.com/code</a>
          </p>
        </div>

        <div className="hero-stage" ref={stageRef}>
          <div className="blob"></div>
          <Sparkle className="hero-sparkle s1" size={28} color="#FFC8D3"/>
          <Sparkle className="hero-sparkle s2" size={22} color="#FFE9D2"/>
          <Sparkle className="hero-sparkle s3" size={36} color="#FFB3C1"/>

          <div className="hero-bubble">mrrp? 🐾</div>

          <div className="hero-chip c1"><span className="emoji">🥛</span> milk break</div>
          <div className="hero-chip c2"><span className="emoji">🌿</span> 100% lazy</div>
          <div className="hero-chip c3"><span className="emoji">💤</span> 14 hr/day</div>

          <div className="hero-cat-wrap">
            <PosterCat stateKey="idle" alwaysAnimate className="hero-cat" alt="A cute kitten sitting" />
          </div>
        </div>
      </div>
    </section>
  );
}

// ---------- Mood Gallery ----------
const MOODS = [
  // `stateKey` indexes CATS/STILLS so MoodCard can render a cheap still
  // poster and swap to the APNG on hover (note peek→peekRight, cling→clingTop).
  { key: 'idle',     stateKey: 'idle',     name: 'Idle',     bg: '#FFE4EA', time: '08:14', speech: 'hi!' },
  { key: 'hungry',   stateKey: 'hungry',   name: 'Hungry',   bg: '#FFE9D2', time: '12:00', speech: 'feed me?' },
  { key: 'eating',   stateKey: 'eating',   name: 'Eating',   bg: '#F6E8CF', time: '12:04', speech: 'om nom' },
  { key: 'petting',  stateKey: 'petting',  name: 'Petting',  bg: '#FFC8D3', time: '14:22', speech: '♥' },
  { key: 'purring',  stateKey: 'purring',  name: 'Purring',  bg: '#FFE4EA', time: '14:30', speech: 'prrrr' },
  { key: 'peek',     stateKey: 'peekRight', name: 'Peeking', bg: '#BFE1F0', time: '16:08', speech: 'boo!' },
  { key: 'cling',    stateKey: 'clingTop', name: 'Hanging',  bg: '#B6D7A8', time: '17:45', speech: 'wheee' },
  { key: 'sleepy',   stateKey: 'sleepy',   name: 'Sleepy',   bg: '#F6E8CF', time: '21:18', speech: 'yawn~' },
  { key: 'dozing',   stateKey: 'dozing',   name: 'Dozing',   bg: '#FFE9D2', time: '22:30', speech: 'zzz' },
  { key: 'sleeping', stateKey: 'sleeping', name: 'Snoozing', bg: '#FFE4EA', time: '03:00', speech: 'zzz...' },
];

function MoodCard({ mood, featured, onSpeak }) {
  const [speaking, setSpeaking] = React.useState(false);
  function trigger(e) {
    setSpeaking(true);
    onSpeak && onSpeak(e, mood.speech);
    clearTimeout(trigger._t);
    trigger._t = setTimeout(() => setSpeaking(false), 1400);
  }
  return (
    <div className={`mood-card ${featured ? 'featured' : ''} ${speaking ? 'speak' : ''}`}
         onClick={trigger}>
      <div className="speech">{mood.speech}</div>
      <div className="mood-img-wrap" style={{ '--bg': mood.bg, background: mood.bg }}>
        {/* Still poster by default; the featured card animates, the rest
            swap to APNG on hover — keeps 9 heavy APNGs off the initial load. */}
        <PosterCat stateKey={mood.stateKey} className="mood-img" alt={mood.name}
                   alwaysAnimate={featured} />
      </div>
      <div className="mood-label">
        <span className="name">{mood.name}</span>
        <span className="time">{mood.time}</span>
      </div>
    </div>
  );
}

function MoodGallery({ onHeart }) {
  return (
    <section className="moods" id="moods">
      <div className="section-head">
        <span className="section-tag">10 moods · all day long</span>
        <h2 className="section-title">
          She has <span className="squiggle">opinions</span>.<br />
          And feelings. And naps.
        </h2>
        <p className="section-sub">
          Tap any mood. Real moods cycle automatically based on the time of day,
          your typing rhythm, and how often you remember to feed her.
        </p>
      </div>
      <div className="moods-grid">
        <MoodCard mood={MOODS[0]} featured onSpeak={onHeart}/>
        {MOODS.slice(1).map(m => <MoodCard key={m.key} mood={m} onSpeak={onHeart} />)}
      </div>
    </section>
  );
}

// ---------- Features ----------
function Features() {
  return (
    <section className="features" id="features">
      <div className="section-head">
        <span className="section-tag">what she does</span>
        <h2 className="section-title">
          Not a wallpaper.<br />
          A <span className="squiggle">whole little life.</span>
        </h2>
      </div>
      <div className="features-grid">
        <div className="feature big">
          <div className="feat-num">01 — companion</div>
          <h3>She lives in the space between your windows.</h3>
          <p>
            Click-through window — single clicks pass straight to the app
            behind her, double-click feeds. She'll snap to the top, peek
            from the left or right, or sit on your dock corner. Always
            there, never in the way.
          </p>
          <span className="feat-stat">◉ zero CPU when idle · click-through</span>
          <div className="feat-illustration">
            <PosterCat stateKey="clingTop" alwaysAnimate alt="Cat hanging from top" />
          </div>
        </div>

        <div className="feature">
          <div className="feat-num">02 — moods</div>
          <h3>14 moods that earn themselves.</h3>
          <p>Idle 5 min → sleepy. 15 → dozing. 30 → curled up sleeping. 24 h no feed → quietly hungry. Sleep progression is a passive decay — never a popup.</p>
          <div className="feat-illustration">
            <PosterCat stateKey="sleepy" alwaysAnimate alt="Sleepy cat" />
          </div>
        </div>

        <div className="feature">
          <div className="feat-num">03 — feed</div>
          <h3>Double-click. She eats a Claude-cookie. A tip bubbles up.</h3>
          <p>Runs <code>claude -p</code> with one of six prompt themes (☕ tip / 💡 prompt / 📰 news / 🤓 TIL / 😆 joke / 🥟 doggerel). Click the bubble to copy the text.</p>
          <div className="feat-illustration">
            <PosterCat stateKey="eating" alwaysAnimate alt="Eating cat" />
          </div>
        </div>

        <div className="feature wide">
          <div className="feat-side-img">
            <PosterCat stateKey="petting" alwaysAnimate alt="Petting cat" />
          </div>
          <div style={{flex: 1}}>
            <div className="feat-num">04 — petting</div>
            <h3>Hover for a second. She tilts into your cursor.</h3>
            <p>
              Hold the mouse over her for ≥1 second and she switches to a
              head-tilted blissful purr. Move the cursor away, she returns
              to idle. Nothing is logged, nothing is pinged — just a small
              quiet exchange.
            </p>
            <span className="feat-stat">♡ 100% local · nothing leaves your machine</span>
          </div>
        </div>
      </div>
    </section>
  );
}

// ---------- How it works ----------
function HowItWorks() {
  return (
    <section className="how" id="how">
      <div className="section-head">
        <span className="section-tag">setup in 30 seconds</span>
        <h2 className="section-title">Get a kitten. <span className="squiggle">Now.</span></h2>
      </div>
      <div className="steps">
        <div className="step">
          <div className="step-num">1</div>
          <div className="step-visual" style={{background:'#FFE4EA', textAlign:'center'}}>
            <span className="mono" style={{fontSize:12,color:'#7A6A5C'}}>brew install --cask</span>
            <br/>
            <span className="mono" style={{fontSize:13,color:'#2A1F17',fontWeight:600}}>anzy-renlab-ai/tap/mypet</span>
          </div>
          <h4>One brew command</h4>
          <p>macOS 13+. Needs the <code>claude</code> CLI on your PATH. No account, no email, no nonsense.</p>
        </div>
        <div className="step">
          <div className="step-num">2</div>
          <div className="step-visual" style={{background:'#FFE9D2'}}>
            <PosterCat stateKey="idle" alwaysAnimate alt="" />
          </div>
          <h4>Open the box</h4>
          <p>Drag mypet to Applications. Launch. Your new kitten appears with a tiny "mrrp".</p>
        </div>
        <div className="step">
          <div className="step-num">3</div>
          <div className="step-visual" style={{background:'#B6D7A8'}}>
            <PosterCat stateKey="purring" alwaysAnimate alt="" />
          </div>
          <h4>That's it</h4>
          <p>She lives there now. Optional: name her. Optional: feel things again.</p>
        </div>
      </div>
    </section>
  );
}

// ---------- Demo strip ----------
function DemoStrip() {
  return (
    <section style={{padding: '40px 0'}}>
      <div className="demo-strip">
        <div>
          <h3>She wanders. <span className="accent">All day.</span></h3>
          <p>
            mypet doesn't just sit there. She crosses your screen at her own pace,
            stops to bat at notifications, and naps on whatever you open last.
          </p>
          <span className="feat-stat" style={{background: 'rgba(255,255,255,0.12)', color: 'rgba(255,255,255,0.85)', borderColor: 'rgba(255,255,255,0.3)'}}>
            🐾 32 unique behaviors · always idle, never annoying
          </span>
        </div>
        <div className="cat-track">
          <div className="desktop">
            <div className="icon i1"></div>
            <div className="icon i2"></div>
            <div className="icon i3"></div>
          </div>
          <img loading="lazy" decoding="async" className="walk-cat" src={CATS.idle} alt="" />
        </div>
      </div>
    </section>
  );
}

// ---------- Love wall ----------
const QUOTES = [
  { c:'pink',  q:"I downloaded this 'for fun' and now I can't work without her hanging from my menubar.", n:'Marin', h:'@marin_tabs', a:'M' },
  { c:'',      q:'Finally an app that doesn\'t want my data. She just wants snacks.', n:'Jules', h:'@jules.dev', a:'J' },
  { c:'cream', q:'My coworkers thought I was losing it because I said "good morning" to my screen.', n:'Theo', h:'@theow', a:'T' },
  { c:'',      q:'10/10 emotional support kitty. She purred me through a deploy.', n:'Riya', h:'@riya.codes', a:'R' },
  { c:'green', q:'I named mine Biscuit. Biscuit is my best friend now.', n:'Sam', h:'@sammich', a:'S' },
  { c:'',      q:'The fact that she gets sleepy at the exact same time as me feels illegal.', n:'Luca', h:'@lucalu', a:'L' },
  { c:'pink',  q:'Replaced my fidget toys. Replaced my mood ring. Maybe replaced my therapist.', n:'Ines', h:'@inesarc', a:'I' },
  { c:'cream', q:'Bought a second monitor just so she has more room.', n:'Owen', h:'@owen.exe', a:'O' },
  { c:'',      q:'My toddler tries to pet the screen now. I have no regrets.', n:'Priya', h:'@priyamom', a:'P' },
];

function LoveWall() {
  return (
    <section className="love" id="love">
      <div className="section-head">
        <span className="section-tag">the love wall</span>
        <h2 className="section-title">What people <span className="squiggle">might say</span><span style={{fontSize: '0.6em', verticalAlign: 'middle', color: 'var(--ink-400)'}}> (fictional, for now)</span></h2>
      </div>
      <div className="love-grid">
        {QUOTES.map((q, i) => (
          <div key={i} className={`love-card ${q.c}`}>
            <div className="quote">"{q.q}"</div>
            <div className="who">
              <div className="avatar">{q.a}</div>
              <div>
                <div className="name">{q.n}</div>
                <div className="handle">{q.h}</div>
              </div>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

// ---------- FAQ ----------
const FAQS = [
  { q: 'Is it really free?', a: 'Yes, fully free. No premium tier, no in-app purchases for kibble. We may add optional cat skins later, but the base kitty is free forever.' },
  { q: 'Will she slow my Mac down?', a: 'Zero CPU when idle (her TimelineView gates 60fps rendering behind a needsAnimation flag). When awake, she draws like any small SwiftUI app.' },
  { q: 'Does she watch what I do?', a: 'No. mypet runs 100% locally. The only network call is your own claude -p when you double-click to feed her — that goes to Anthropic on your existing Claude Code login, not to us.' },
  { q: 'Does she cost extra tokens?', a: 'She spends YOUR Claude Code subscription quota. One feed = one claude -p call (~10-150 tokens depending on the prompt theme). No separate API key, no extra bill.' },
  { q: 'What about my actual cat?', a: 'mypet is not a replacement for a real cat. Please feed your actual cat. Send us pictures.' },
];

function FAQ() {
  const [open, setOpen] = React.useState(0);
  return (
    <section className="faq" id="faq">
      <div className="section-head">
        <span className="section-tag">questions</span>
        <h2 className="section-title">You're <span className="squiggle">curious</span>.<br/>She's curious about you too.</h2>
      </div>
      <div className="faq-list">
        {FAQS.map((f, i) => (
          <div key={i} className={`faq-item ${open === i ? 'open' : ''}`}>
            <button className="faq-q" onClick={() => setOpen(open === i ? -1 : i)}>
              <span>{f.q}</span>
              <span className="toggle">+</span>
            </button>
            <div className="faq-a">
              <div className="faq-a-inner">{f.a}</div>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

// ---------- Final CTA ----------
function FinalCTA({ onHeartBurst }) {
  return (
    <section>
      <div className="cta-final">
        <img loading="lazy" decoding="async" className="floating-cat f1" src={CATS.peekRight} alt="" />
        <img loading="lazy" decoding="async" className="floating-cat f2" src={CATS.idle} alt="" />
        <img loading="lazy" decoding="async" className="floating-cat f3" src={CATS.purring} alt="" />
        <img loading="lazy" decoding="async" className="floating-cat f4" src={CATS.sleepy} alt="" />
        <h2>Your screen is too lonely.<br/>Adopt a kitten.</h2>
        <p>Open source. macOS 13+. MIT license. Spends your existing Claude Code quota — no separate API key.</p>
        <a className="btn-primary"
           href="https://github.com/anzy-renlab-ai/mypet"
           target="_blank" rel="noopener"
           onClick={(e) => onHeartBurst(e.clientX, e.clientY)}>
          <span>Take her home</span>
          <span className="os-tag">GitHub · free</span>
        </a>
      </div>
    </section>
  );
}

// ---------- Footer ----------
function Footer() {
  return (
    <footer className="footer">
      <div className="footer-grid">
        <div className="footer-col footer-brand">
          <div className="logo"><span style={{width:12,height:12,background:'#F47C92',borderRadius:'50%',border:'2px solid #2A2018',display:'inline-block'}}></span> mypet</div>
          <p>A fluffy desktop cat that spends your Claude Code tokens. macOS 13+, MIT-licensed code, copyrighted artwork. Made with care.</p>
        </div>
        <div className="footer-col">
          <h5>Product</h5>
          <a href="https://github.com/anzy-renlab-ai/mypet" target="_blank" rel="noopener">GitHub</a>
          <a href="https://github.com/anzy-renlab-ai/mypet/releases" target="_blank" rel="noopener">Releases</a>
          <a href="https://github.com/anzy-renlab-ai/mypet#readme" target="_blank" rel="noopener">README</a>
          <a href="https://github.com/anzy-renlab-ai/mypet/issues" target="_blank" rel="noopener">Issues</a>
        </div>
        <div className="footer-col">
          <h5>Requirements</h5>
          <a href="https://docs.anthropic.com/claude-code" target="_blank" rel="noopener">Claude Code CLI</a>
          <a href="https://www.apple.com/macos" target="_blank" rel="noopener">macOS 13+</a>
          <a href="https://github.com/anzy-renlab-ai/mypet/blob/master/LICENSE" target="_blank" rel="noopener">MIT license</a>
          <a href="https://github.com/anzy-renlab-ai/mypet/blob/master/Sources/MyPet/Resources/sprites/LICENSE" target="_blank" rel="noopener">Artwork license</a>
        </div>
        <div className="footer-col">
          <h5>Links</h5>
          <a href="https://github.com/anzy-renlab-ai/mypet" target="_blank" rel="noopener">GitHub</a>
          <a href="https://github.com/anzy-renlab-ai" target="_blank" rel="noopener">renlab-ai</a>
          <a href={KOFI_URL} target="_blank" rel="noopener">☕ Ko-fi</a>
          <a href="https://mypet.renlab.ai">mypet.renlab.ai</a>
        </div>
      </div>
      <div className="footer-bottom">
        <span>© 2026 alvin (anzy-renlab-ai) · made with ♥ and many naps</span>
        <span>v0.1 · 151 tests passing</span>
      </div>
    </footer>
  );
}

// ---------- Ambient cats ----------
function AmbientCats({ density, motion, onHeartBurst }) {
  const [peek, setPeek] = React.useState(false);

  React.useEffect(() => {
    if (density === 'one') return;
    function onScroll() {
      const scrolled = window.scrollY;
      const max = document.body.scrollHeight - window.innerHeight;
      const pct = scrolled / max;
      // peek triggers between 25–55% scroll
      setPeek(pct > 0.25 && pct < 0.55);
    }
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, [density]);

  if (density === 'one') return null;

  return (
    <div className="ambient-cats" style={{ animationPlayState: motion === 'off' ? 'paused' : 'running' }}>
      {density === 'many' && (
        <img loading="lazy" decoding="async" className="ambient-cat cling" src={CATS.clingTop} alt="" onClick={(e) => onHeartBurst(e.clientX, e.clientY)} />
      )}
      <img loading="lazy" decoding="async" className={`ambient-cat peek-r ${peek ? 'show' : ''}`} src={CATS.peekRight} alt="" onClick={(e) => onHeartBurst(e.clientX, e.clientY)} />
      {density === 'many' && motion !== 'off' && (
        <img loading="lazy" decoding="async" className="ambient-cat roam" src={CATS.idle} alt="" onClick={(e) => onHeartBurst(e.clientX, e.clientY)} />
      )}
    </div>
  );
}

// expose
Object.assign(window, {
  CATS, Sparkle, Nav, Hero, MoodGallery, Features, HowItWorks,
  DemoStrip, LoveWall, FAQ, FinalCTA, Footer, AmbientCats,
});
