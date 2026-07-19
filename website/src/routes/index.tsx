import { createFileRoute } from "@tanstack/react-router";
import { Cta } from "../components/Cta";
import { FeatureRows } from "../components/FeatureRows";
import { Footer } from "../components/Footer";
import { Hero } from "../components/Hero";
import { Nav } from "../components/Nav";
import { Privacy } from "../components/Privacy";
import { ProductShowcase } from "../components/ProductShowcase";
import { WorkGrid } from "../components/WorkGrid";

export const Route = createFileRoute("/")({
  component: LandingPage,
});

function LandingPage() {
  return (
    <div className="min-h-screen">
      <Nav />
      <main>
        <Hero />
        <FeatureRows />
        <WorkGrid />
        <ProductShowcase />
        <Privacy />
        <Cta />
      </main>
      <Footer />
    </div>
  );
}
