import { createFileRoute } from "@tanstack/react-router";
import { LegalPage, LegalSection } from "../components/LegalPage";

export const Route = createFileRoute("/terms")({
  head: () => ({
    meta: [
      { title: "Terms of Service — Dayline" },
      { name: "description", content: "Terms governing use of the Dayline macOS app." },
    ],
  }),
  component: TermsOfService,
});

function TermsOfService() {
  return (
    <LegalPage
      title="Terms of Service"
      summary="These terms govern your use of the Dayline macOS app and website."
      updated="July 19, 2026"
    >
      <LegalSection title="Using Dayline">
        <p>
          You may use Dayline for lawful personal or business purposes. You are
          responsible for the accounts you connect, the content you access, and
          complying with the rules of Google, Linear, Apple, and any other
          services you use through Dayline.
        </p>
      </LegalSection>

      <LegalSection title="Third-party services">
        <p>
          Dayline integrates with services operated by third parties. Their
          availability, data, security, and terms are controlled by those
          providers. Dayline is not responsible for third-party service outages,
          account restrictions, API changes, or content.
        </p>
      </LegalSection>

      <LegalSection title="No warranty">
        <p>
          Dayline is provided on an “as is” and “as available” basis without
          warranties of any kind. Calendar events, issue data, notifications,
          and other information may be delayed, incomplete, or unavailable. Do
          not rely on Dayline as the sole source for critical schedules or
          deadlines.
        </p>
      </LegalSection>

      <LegalSection title="Limitation of liability">
        <p>
          To the fullest extent permitted by law, Dayline&apos;s developers and
          contributors are not liable for indirect, incidental, special,
          consequential, or punitive damages, or for loss of data, profits,
          access, or business arising from your use of Dayline.
        </p>
      </LegalSection>

      <LegalSection title="Changes and termination">
        <p>
          Dayline may change, suspend, or discontinue features, and these terms
          may be updated as the product evolves. You may stop using Dayline at
          any time and disconnect your accounts from Settings.
        </p>
      </LegalSection>

      <LegalSection title="Contact">
        <p>
          Questions about these terms can be sent to{
          " "
          }<a
            href="mailto:info@liquidium.fi"
            className="text-ink underline decoration-line underline-offset-4 hover:decoration-ember"
          >
            info@liquidium.fi
          </a>.
        </p>
      </LegalSection>
    </LegalPage>
  );
}
