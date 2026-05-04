package pack

// Manifest is the strongly-typed view of manifest.json.
// JSON Schema validation runs first; this struct is for code that needs the values.
type Manifest struct {
	SchemaVersion  string         `json:"schemaVersion"`
	ID             string         `json:"id"`
	Name           string         `json:"name"`
	Version        string         `json:"version"`
	Description    string         `json:"description,omitempty"`
	Language       Language       `json:"language"`
	UILanguage     string         `json:"uiLanguage,omitempty"`
	Level          string         `json:"level,omitempty"`
	Author         Author         `json:"author"`
	License        string         `json:"license"`
	Homepage       string         `json:"homepage,omitempty"`
	Repository     *Repository    `json:"repository,omitempty"`
	Tags           []string       `json:"tags,omitempty"`
	Lessons        []LessonRef    `json:"lessons"`
	Dependencies   []Dependency   `json:"dependencies,omitempty"`
	MinSDKVersion  string         `json:"minSdkVersion,omitempty"`
}

type Language struct {
	Code       string `json:"code"`
	Name       string `json:"name"`
	NativeName string `json:"nativeName,omitempty"`
	Script     string `json:"script,omitempty"`
	Direction  string `json:"direction,omitempty"`
}

type Author struct {
	Name  string `json:"name"`
	URL   string `json:"url,omitempty"`
	Email string `json:"email,omitempty"`
}

type Repository struct {
	Type string `json:"type"`
	URL  string `json:"url"`
}

type LessonRef struct {
	ID    string `json:"id"`
	File  string `json:"file"`
	Title string `json:"title,omitempty"`
	Order int    `json:"order,omitempty"`
}

type Dependency struct {
	ID      string `json:"id"`
	Version string `json:"version"`
}
