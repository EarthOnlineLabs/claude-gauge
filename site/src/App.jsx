import React from "react";
import { LangProvider } from "./lang.jsx";
import { Header } from "./components/Header.jsx";
import { Hero } from "./components/Hero.jsx";
import { Privacy } from "./components/Privacy.jsx";
import { Install } from "./components/Install.jsx";
import { Features } from "./components/Features.jsx";
import { Footer } from "./components/Footer.jsx";

export function App() {
  return (
    <LangProvider>
      <Header />
      <Hero />
      <Privacy />
      <Install />
      <Features />
      <Footer />
    </LangProvider>
  );
}
