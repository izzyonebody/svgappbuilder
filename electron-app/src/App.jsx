import React, { useState } from "react";
import SvgCanvas from "./canvas/SvgCanvas";
import api from "./services/api";

export default function App() {
  const [selected, setSelected] = useState(null);
  const [log, setLog] = useState("");

  const handleSuggest = async () => {
    const prompt = `Suggest a header + hero section for a website. Provide React + SVG snippet for a hero section.`;
    try {
      const res = await api.generate({ model: "mistral-7b-instruct", prompt, max_tokens: 600 });
      setLog(JSON.stringify(res, null, 2));
    } catch (e) {
      setLog(String(e));
    }
  };

  return (
    <div style={{ display: "flex", height: "100vh" }}>
      <div style={{ flex: 1, borderRight: "1px solid #ddd" }}>
        <SvgCanvas />
      </div>
      <div style={{ width: 420, padding: 12 }}>
        <h3>Assistant</h3>
        <button onClick={handleSuggest}>Ask AI for Suggestion</button>
        <pre style={{whiteSpace: "pre-wrap", maxHeight: "80vh", overflow:"auto"}}>{log}</pre>
      </div>
    </div>
  );
}
