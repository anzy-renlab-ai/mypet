/* mypet — app entry */

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "theme": "blush",
  "bgPattern": "dots",
  "density": "few",
  "motion": "on"
}/*EDITMODE-END*/;

const THEMES = {
  blush: { name: 'Blush cream', vars: { '--blush-100':'#FFE4EA','--blush-200':'#FFC8D3','--blush-300':'#FFA8B8','--blush-500':'#F47C92', '--cream-100':'#FBF4E6' } },
  honey: { name: 'Honey butter', vars: { '--blush-100':'#FFF2D6','--blush-200':'#FFE0A6','--blush-300':'#F8C66D','--blush-500':'#D69437', '--cream-100':'#FEF7E5' } },
  matcha:{ name: 'Matcha milk',  vars: { '--blush-100':'#E6F0D9','--blush-200':'#C5E0A8','--blush-300':'#9DC56F','--blush-500':'#6CA13E', '--cream-100':'#F6F4E8' } },
  taro:  { name: 'Taro dream',   vars: { '--blush-100':'#EFE2F5','--blush-200':'#D8BFE5','--blush-300':'#B795D0','--blush-500':'#8A5BB0', '--cream-100':'#F7F2F8' } },
};

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [hearts, setHearts] = React.useState([]);

  // Apply theme palette to :root
  React.useEffect(() => {
    const vars = THEMES[t.theme]?.vars || THEMES.blush.vars;
    const root = document.documentElement;
    Object.entries(vars).forEach(([k, v]) => root.style.setProperty(k, v));
  }, [t.theme]);

  function heartBurst(x, y) {
    const id = Math.random().toString(36).slice(2);
    const burst = Array.from({ length: 5 }).map((_, i) => ({
      id: id + '-' + i,
      x: x + (Math.random() - 0.5) * 30,
      y: y + (Math.random() - 0.5) * 10,
      dx: (Math.random() - 0.5) * 80,
      emoji: ['♥','♡','🐾','✨','♥'][Math.floor(Math.random()*5)],
    }));
    setHearts(h => [...h, ...burst]);
    setTimeout(() => setHearts(h => h.filter(p => !burst.find(b => b.id === p.id))), 1300);
  }

  return (
    <>
      <div className={`bg-pattern ${t.bgPattern}`}></div>
      <div id="app">
        <Nav />
        <Hero onHeartBurst={heartBurst} />
        <MoodGallery onHeart={(e, sp) => heartBurst(e.clientX, e.clientY)} />
        <Features />
        <DemoStrip />
        <HowItWorks />
        <LoveWall />
        <FAQ />
        <FinalCTA onHeartBurst={heartBurst} />
        <Footer />
      </div>
      <AmbientCats density={t.density} motion={t.motion} onHeartBurst={heartBurst}/>

      {hearts.map(h => (
        <div key={h.id} className="heart-particle"
             style={{ left: h.x, top: h.y, '--dx': h.dx + 'px' }}>{h.emoji}</div>
      ))}

      <TweaksPanel title="Tweaks">
        <TweakSection title="Theme">
          <TweakSelect
            label="Palette"
            value={t.theme}
            onChange={v => setTweak('theme', v)}
            options={Object.entries(THEMES).map(([k, v]) => ({ value: k, label: v.name }))}
          />
        </TweakSection>
        <TweakSection title="Background">
          <TweakRadio
            label="Pattern"
            value={t.bgPattern}
            onChange={v => setTweak('bgPattern', v)}
            options={[
              { value: 'dots',  label: 'Dots' },
              { value: 'grid',  label: 'Grid' },
              { value: 'paws',  label: 'Paws' },
              { value: 'plain', label: 'Plain' },
            ]}
          />
        </TweakSection>
        <TweakSection title="Kitties">
          <TweakRadio
            label="Cat density"
            value={t.density}
            onChange={v => setTweak('density', v)}
            options={[
              { value: 'one',  label: 'One' },
              { value: 'few',  label: 'A few' },
              { value: 'many', label: 'Many' },
            ]}
          />
          <TweakRadio
            label="Animation"
            value={t.motion}
            onChange={v => setTweak('motion', v)}
            options={[
              { value: 'on',  label: 'On' },
              { value: 'off', label: 'Off' },
            ]}
          />
        </TweakSection>
      </TweaksPanel>
    </>
  );
}

// useTweaks comes from tweaks-panel.jsx
ReactDOM.createRoot(document.getElementById('root')).render(<App />);
