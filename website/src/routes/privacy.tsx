import { createFileRoute } from "@tanstack/react-router";
import { LegalPage, LegalSection } from "../components/LegalPage";

export const Route = createFileRoute("/privacy")({
  head: () => ({
    meta: [
      { title: "Privacy Policy — Dayline" },
      {
        name: "description",
        content: "How Dayline handles Google Calendar, Apple Reminders, Linear, GitHub, and local note data.",
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
      updated="August 2, 2026"
    >
      <LegalSection title="Google user data Dayline accesses">
        <p>
          When you connect a Google account, Dayline requests only the read-only{
          " "
          }<code>https://www.googleapis.com/auth/calendar.readonly</code> scope.
          Dayline accesses the primary calendar identifier, which is normally
          your Google account email address, and your readable calendar list,
          including calendar identifiers, names, primary-calendar status, and
          Google&apos;s selected-calendar status.
        </p>
        <p>
          For calendars you enable in Dayline, it reads timed event records in a
          limited window covering the remaining events today and tomorrow. It
          processes event identifiers, titles, start and end times, cancellation
          status, locations, Google Calendar links, and conferencing links needed
          to display, deduplicate, open, and notify you about those events.
          All-day events are not included in Dayline&apos;s agenda. Dayline does not
          create, edit, or delete Google Calendar data.
        </p>
      </LegalSection>

      <LegalSection title="Other data Dayline accesses">
        <p>
          Dayline connects to Linear or GitHub only when you choose to use those
          issue features. It reads the account or workspace identity, available
          teams or repositories, and issue data needed for the menu and actions
          you request. Depending on the issue filter you choose, that is either
          only issues assigned to you or all open issues in the Linear teams or
          GitHub repositories you select. When you create a Linear issue or
          change an issue&apos;s status, priority, due date, labels, or assignee,
          Dayline sends that requested change directly to Linear or GitHub. It
          does not make issue changes without your action.
        </p>
        <p>
          When you connect Apple Reminders, Dayline asks macOS for full Reminders
          access and uses EventKit directly on your Mac. It reads the names and
          identifiers of available reminder lists and the incomplete reminders
          in lists you enable, including their titles, notes, attached URLs,
          priority, due date, and recurrence status. Dayline changes or creates a
          reminder only when you request that action.
        </p>
        <p>
          Quick notes you create in Dayline are stored locally on your Mac and
          are not sent to Google, Linear, GitHub, or a Dayline service.
        </p>
      </LegalSection>

      <LegalSection title="Where data is stored">
        <p>
          OAuth access and refresh tokens are stored in the macOS Keychain.
          Linked Google account labels, calendar identifiers and names, and your
          enabled-calendar selections are stored in local app preferences.
          Google Calendar event data is held only in app memory for display and
          alerts; Dayline does not persist an event cache to disk. Linear and
          GitHub account selections and enabled Apple Reminders lists are also
          stored in local preferences. Reminder data is held in app memory and
          remains stored by Apple Reminders. Notes
          are stored in Dayline&apos;s local Application Support directory.
          Dayline also keeps a small, bounded diagnostic log in Application
          Support containing only app lifecycle, refresh counts, and action
          breadcrumbs. It does not record account identifiers, calendar or issue
          contents, notes, URLs, or authentication data.
        </p>
        <p>
          Dayline talks directly from your Mac to Google, Linear, and GitHub over
          HTTPS and accesses Apple Reminders locally through macOS EventKit. It
          does not copy Google user data or other connected-account data
          to a Dayline-operated server. If
          you submit feedback, the feedback is sent through Dayline&apos;s
          Cloudflare Worker and posted as a public issue in Dayline&apos;s GitHub
          repository. The Worker does not retain the feedback message or
          anonymous app and system information. If you explicitly include a
          diagnostic archive, the Worker stores that archive behind the public,
          unguessable link added to the issue for up to 30 days.
        </p>
        <p>
          Cloudflare necessarily processes the connection&apos;s IP address. To
          prevent spam, the Worker converts it to a secret-keyed hash used only
          for rate limiting; the raw address is never added to your feedback or
          public GitHub issue. Cloudflare&apos;s operational Worker logs may retain
          request metadata, including the IP address, for up to seven days.
        </p>
      </LegalSection>

      <LegalSection title="How data is used and shared">
        <p>
          Google Calendar data is used solely to provide Dayline&apos;s user-facing
          calendar list, agenda, event links, menu bar countdown, and meeting
          alerts. Dayline does not sell Google user data, use it for advertising,
          profiling, credit decisions, or data brokerage, or share or transfer it
          to third parties. Google user data is not included in feedback reports.
          Dayline does not use Google Workspace API data to develop, improve, or
          train generalized or non-personalized artificial intelligence or
          machine-learning models.
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
          name, device name, IP address, accounts, calendar, issue, or reminder
          data, notes, OAuth tokens, or logs. A separate Include diagnostics option
          can explicitly add the diagnostic archive described below. Feedback
          and anything you choose to include are public on GitHub, so you should
          not enter personal or sensitive information.
        </p>
        <p>
          If you explicitly choose Export Diagnostics, Dayline creates a ZIP on
          your Mac containing its bounded diagnostic log, app and system version
          information, and up to five recent native macOS crash reports. Dayline
          does not upload a manually exported archive. If you separately select
          Include diagnostics when submitting feedback, Dayline creates the same
          ZIP, uploads it with the feedback, and adds a public download link to
          the GitHub issue for 30 days. Native crash reports can contain system
          and device identifiers, loaded-image information, and process metadata.
        </p>
      </LegalSection>

      <LegalSection title="Your control and retention">
        <p>
          You can disable individual calendars at any time. Disconnecting a
          Google account revokes its OAuth token, deletes that account&apos;s access
          and refresh tokens from Keychain, removes its saved account and
          calendar selections from local preferences, and removes its event data
          from memory without affecting other connected accounts. Quitting
          Dayline clears all in-memory Google Calendar event data. You can also
          revoke Dayline from your Google Account permissions page.
        </p>
        <p>
          Disconnecting Apple Reminders in Dayline clears its reminder data from
          memory and stops Dayline from reading or changing reminders. macOS
          controls the underlying permission; you can revoke it in System
          Settings. Disabling an individual list removes that list from Dayline
          without deleting or changing reminders in Apple&apos;s app.
        </p>
        <p>
          Dayline retains Google account metadata and credentials only while the
          account remains connected. To delete this local Google data, disconnect
          the account in Dayline Settings. Google may retain information under
          its own privacy policy. Deleting Dayline&apos;s local notes file removes
          your saved notes, and Linear or GitHub access can be revoked from those
          services&apos; security settings.
        </p>
        <p>
          Submitted feedback is retained publicly in the Dayline GitHub
          repository until a maintainer edits or removes it. You can use the
          contact address below to request removal. An explicitly included
          diagnostic archive is deleted automatically after 30 days, at which
          point its download link stops working.
        </p>
        <p>
          Dayline rotates its diagnostic log at approximately 512 KB and keeps
          at most the current and immediately previous file. You can delete
          those files from Dayline&apos;s Diagnostics folder in Application
          Support. Exporting diagnostics creates a separate archive wherever you
          choose to save it; Dayline does not manage or upload that manually
          exported copy.
        </p>
      </LegalSection>

      <LegalSection title="Security">
        <p>
          Dayline protects data in transit with HTTPS. Google and Linear sign-in
          use OAuth 2.0 with PKCE, Dayline requests the narrowest practical
          permissions, credentials are stored in the macOS Keychain rather than
          app preferences, and the app does not ship OAuth client secrets. No
          security measure is perfect. Apple Reminders access is controlled by
          macOS privacy permissions and stays on the Mac. Dayline is designed to minimize the
          data it handles, retains, and transfers.
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
