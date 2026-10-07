-- Copy to local.lua (gitignored) and adjust.
return {
  browser = {
    -- Profile label -> email domain, or full email, of the Chrome profile to open
    profiles = {
      work = "example.com",
      personal = "me@gmail.com",
    },
    -- First match wins. match: URL substrings; source: optional opening app path
    rules = {
      { profile = "work", match = { "jira", "teams.microsoft" } },
      { profile = "work", source = "/Applications/Slack.app", match = { "google" } },
      { profile = "personal", match = { "youtube" } },
    },
  },
}
