import { createFileRoute } from "@tanstack/react-router";
import { LegalPage, LegalSection } from "../components/LegalPage";

export const Route = createFileRoute("/privacy")({
  head: () => ({
    meta: [
      { title: "Privacy Policy — Dayline" },
      {
        name: "description",
        content: "How Dayline handles Google Calendar, Linear, and local note data.",
      },
    ],
  }),
  component: PrivacyPolicy,
});

function PrivacyPolicy() {
  return (
    <LegalPage
      title="Privacy Policy"
      summary="Dayline is local-first software. It has no Dayline account system, advertising, analytics, or tracking. Only feedback you deliberately submit is sent through a Dayline service."
      updated="July 21, 2026"
    >
      <LegalSection title="What Dayline accesses">
        <p>
          With your permission, Dayline reads your Google Calendar account
          identity, calendar list, and timed calendar events. It uses this data
          only to let you choose calendars and display your agenda. Dayline also
          connects to Linear when you choose to use its issue features.
        </p>
        <p>
          Quick notes you create in Dayline are stored locally on your Mac and
          are not sent to Google, Linear, or a Dayline service.
        </p>
      </LegalSection>

      <LegalSection title="Where data is stored">
        <p>
          OAuth tokens are stored in the macOS Keychain. Linked Google account
          labels and calendar selections are stored in local app preferences.
          Calendar events and Linear issues are held in memory for display.
          Notes are stored in Dayline&apos;s local Application Support directory.
        </p>
        <p>
          Dayline talks directly from your Mac to Google and Linear over HTTPS.
          It does not copy your account data to a Dayline-operated server. If
          you submit feedback, the feedback is sent through Dayline&apos;s
          Cloudflare Worker and posted as a public issue in Dayline&apos;s GitHub
          repository. The Worker does not retain the feedback.
        </p>
        <p>
          Cloudflare necessarily processes the connection&apos;s IP address. To
          prevent spam, the Worker uses it transiently and keeps only a
          short-lived, secret-keyed hash for rate limiting; Dayline does not
          store the raw address.
        </p>
      </LegalSection>

      <LegalSection title="How data is used and shared">
        <p>
          Google Calendar data is used solely to provide Dayline&apos;s calendar
          features. Dayline does not sell personal data, use it for advertising,
          or share it with data brokers. Data is disclosed only to the service
          you intentionally interact with, such as Google or Linear, as needed
          to perform your requested action.
        </p>
        <p>
          Dayline&apos;s use and transfer to any other app of information received
          from Google APIs adheres to the{
          " "
          }<a
            href="https://developers.google.com/terms/api-services-user-data-policy"
            className="text-ink underline decoration-line underline-offset-4 hover:decoration-ember"
          >
            Google API Services User Data Policy
          </a>, including its Limited Use requirements.
        </p>
        <p>
          Feedback may optionally include only the Dayline version and build,
          macOS version, and chip type. It never automatically includes your
          name, device name, IP address, accounts, calendar or Linear data,
          notes, OAuth tokens, or logs. Feedback and included system information
          are public on GitHub, so you should not enter personal or sensitive
          information.
        </p>
      </LegalSection>

      <LegalSection title="Your control and retention">
        <p>
          You can disable individual calendars at any time. Disconnecting an
          account revokes and deletes that account&apos;s local OAuth credentials and
          removes its Dayline configuration without affecting other accounts.
          Deleting Dayline&apos;s local notes file removes your saved notes.
        </p>
        <p>
          Google and Linear may retain information under their own privacy
          policies. You can also revoke Dayline from your Google Account or
          Linear workspace security settings.
        </p>
        <p>
          Submitted feedback is retained publicly in the Dayline GitHub
          repository until a maintainer edits or removes it. You can use the
          contact address below to request removal.
        </p>
      </LegalSection>

      <LegalSection title="Security">
        <p>
          Dayline uses OAuth 2.0 with PKCE, requests the narrowest practical
          permissions, stores tokens in Keychain, and does not ship OAuth client
          secrets in the app. No security measure is perfect, but Dayline is
          designed to minimize the data it handles and where that data travels.
        </p>
      </LegalSection>

      <LegalSection title="Changes and contact">
        <p>
          This policy may be updated when Dayline&apos;s features or legal
          requirements change. Material changes will be reflected by the date at
          the top of this page.
        </p>
        <p>
          Questions or privacy requests can be sent to{
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
