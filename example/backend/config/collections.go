// Package config holds the lab backend constants.
package config

// Collection names used by the lab backend.
const (
	UsersCollection    = "users"
	ProjectsCollection = "projects"
	TasksCollection    = "tasks"
	PostsCollection    = "posts"
	NotesCollection    = "notes"
	LockedCollection   = "locked"
	EventsCollection   = "events"
	BigCollection      = "big"
)

// Automation-safe lab credentials (no `!`, `$`, `&` for adb input text).
const (
	LabUserEmail       = "lab@example.com"
	LabUserPassword    = "Labpass123"
	LabUser2Email      = "lab2@example.com"
	LabSuperuserEmail  = "admin@example.com"
	LabSuperuserPasswd = "Adminpass123"
)

// Superuser used by the package's integration tests under test/.
const (
	TestSuperuserEmail  = "test@admin.com"
	TestSuperuserPasswd = "Password123"
)
