// Package services holds the lab seeding and server-side mutation helpers.
package services

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"math/rand/v2"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/filesystem"

	"pocketbase_drift_example_backend/config"
)

// photoLike renders a w x h JPEG with gradients and noise so the encoded
// size and decode cost resemble a real phone photo.
func photoLike(w, h int, seed uint64) ([]byte, error) {
	r := rand.New(rand.NewPCG(seed, seed*7919))
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	br, bg, bb := r.IntN(200), r.IntN(200), r.IntN(200)
	for y := range h {
		for x := range w {
			n := r.IntN(40)
			img.Set(x, y, color.RGBA{
				R: uint8((br + x*255/w + n) % 256),
				G: uint8((bg + y*255/h + n) % 256),
				B: uint8((bb + (x+y)*128/(w+h) + n) % 256),
				A: 255,
			})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 85}); err != nil {
		return nil, fmt.Errorf("failed to encode jpeg: %w", err)
	}
	return buf.Bytes(), nil
}

func ensureUser(app core.App, email, password, name string) (*core.Record, error) {
	if rec, err := app.FindAuthRecordByEmail(config.UsersCollection, email); err == nil {
		return rec, nil
	}
	col, err := app.FindCollectionByNameOrId(config.UsersCollection)
	if err != nil {
		return nil, fmt.Errorf("failed to find users: %w", err)
	}
	rec := core.NewRecord(col)
	rec.SetEmail(email)
	rec.SetPassword(password)
	rec.SetVerified(true)
	rec.Set("name", name)
	if err := app.Save(rec); err != nil {
		return nil, fmt.Errorf("failed to save user %s: %w", email, err)
	}
	return rec, nil
}

// Seed creates the lab users, the lab and package-test superusers and the
// photo posts once.
func Seed(app core.App, postCount int) error {
	su, err := app.FindCollectionByNameOrId(core.CollectionNameSuperusers)
	if err != nil {
		return fmt.Errorf("failed to find superusers: %w", err)
	}
	superusers := [][2]string{
		{config.LabSuperuserEmail, config.LabSuperuserPasswd},
		{config.TestSuperuserEmail, config.TestSuperuserPasswd},
	}
	for _, cred := range superusers {
		if _, err := app.FindAuthRecordByEmail(su, cred[0]); err == nil {
			continue
		}
		rec := core.NewRecord(su)
		rec.SetEmail(cred[0])
		rec.SetPassword(cred[1])
		if err := app.Save(rec); err != nil {
			return fmt.Errorf("failed to save superuser %s: %w", cred[0], err)
		}
	}
	// Batch API is off by default; the package's $createBatch needs it.
	if s := app.Settings(); !s.Batch.Enabled {
		s.Batch.Enabled = true
		s.Batch.MaxRequests = 100
		if err := app.Save(s); err != nil {
			return fmt.Errorf("failed to enable batch api: %w", err)
		}
	}
	author, err := ensureUser(app, config.LabUserEmail, config.LabUserPassword, "Lab User")
	if err != nil {
		return err
	}
	if _, err := ensureUser(app, config.LabUser2Email, config.LabUserPassword, "Lab User Two"); err != nil {
		return err
	}

	existing, err := app.CountRecords(config.PostsCollection)
	if err != nil {
		return fmt.Errorf("failed to count posts: %w", err)
	}
	if existing > 0 {
		return nil
	}

	photos := make([][]byte, 6)
	for i := range photos {
		if photos[i], err = photoLike(2400, 1600, uint64(i+1)); err != nil {
			return err
		}
	}
	posts, err := app.FindCollectionByNameOrId(config.PostsCollection)
	if err != nil {
		return fmt.Errorf("failed to find posts: %w", err)
	}
	for i := range postCount {
		rec := core.NewRecord(posts)
		rec.Set("title", fmt.Sprintf("Post %03d", i))
		rec.Set("body", fmt.Sprintf("Body of post %d. Lorem ipsum dolor sit amet.", i))
		rec.Set("author", author.Id)
		rec.Set("likes", i%17)
		rec.Set("status", "published")
		files := []any{}
		for j := range 1 + i%2 {
			f, err := filesystem.NewFileFromBytes(photos[(i+j)%len(photos)], fmt.Sprintf("photo_%d_%d.jpg", i, j))
			if err != nil {
				return fmt.Errorf("failed to build file: %w", err)
			}
			files = append(files, f)
		}
		rec.Set("images", files)
		if err := app.Save(rec); err != nil {
			return fmt.Errorf("failed to save post %d: %w", i, err)
		}
	}
	return nil
}

// SeedBig inserts count rows into the `big` collection in one transaction.
func SeedBig(app core.App, count int, group string) error {
	col, err := app.FindCollectionByNameOrId(config.BigCollection)
	if err != nil {
		return fmt.Errorf("failed to find big: %w", err)
	}
	return app.RunInTransaction(func(tx core.App) error {
		for i := range count {
			rec := core.NewRecord(col)
			rec.Set("name", fmt.Sprintf("%s-%06d", group, i))
			rec.Set("n", i)
			rec.Set("grp", group)
			if err := tx.Save(rec); err != nil {
				return fmt.Errorf("failed to save big row %d: %w", i, err)
			}
		}
		return nil
	})
}
