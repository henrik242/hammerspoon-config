-- Copy to local.lua (gitignored) and adjust.
return {
  browser = {
    -- Profile label -> email domain or full email of the signed-in account,
    -- or { browser = "chrome"|"brave", dir = "Default" }
    -- (profile directory, shown in chrome://version)
    profiles = {
      work = "example.com",
      personal = { browser = "brave", dir = "Default" },
    },
    -- First match wins. match: URL substrings; source: optional opening app path
    rules = {
      { profile = "work", match = { "jira", "teams.microsoft" } },
      { profile = "work", source = "/Applications/Slack.app", match = { "google" } },
      { profile = "personal", match = { "youtube" } },
    },
  },
}
