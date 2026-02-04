package main

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"runtime"
	"strconv"

	"github.com/go-chi/chi/v5"
	_ "github.com/mattn/go-sqlite3"
)

type Book struct {
	ID     int    `json:"id"`
	Title  string `json:"title"`
	Author string `json:"author"`
	Year   int    `json:"year"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func initDB(db *sql.DB) {
	db.Exec("PRAGMA journal_mode=WAL")

	db.Exec(`CREATE TABLE IF NOT EXISTS books (
		id INTEGER PRIMARY KEY,
		title TEXT NOT NULL,
		author TEXT NOT NULL,
		year INTEGER NOT NULL
	)`)

	stmt, _ := db.Prepare("INSERT OR IGNORE INTO books (id, title, author, year) VALUES (?, ?, ?, ?)")
	defer stmt.Close()

	seeds := []Book{
		{1, "The Rust Programming Language", "Steve Klabnik", 2019},
		{2, "The Go Programming Language", "Alan Donovan", 2015},
		{3, "Designing Data-Intensive Applications", "Martin Kleppmann", 2017},
		{4, "Clean Code", "Robert C. Martin", 2008},
		{5, "Structure and Interpretation of Computer Programs", "Harold Abelson", 1996},
	}
	for _, b := range seeds {
		stmt.Exec(b.ID, b.Title, b.Author, b.Year)
	}
}

func main() {
	db, err := sql.Open("sqlite3", "books.db")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	initDB(db)

	db.SetMaxOpenConns(runtime.NumCPU())
	db.SetMaxIdleConns(runtime.NumCPU())
	db.SetConnMaxLifetime(0)

	listStmt, err := db.Prepare("SELECT id, title, author, year FROM books")
	if err != nil {
		log.Fatal(err)
	}
	defer listStmt.Close()

	getStmt, err := db.Prepare("SELECT id, title, author, year FROM books WHERE id = ?")
	if err != nil {
		log.Fatal(err)
	}
	defer getStmt.Close()

	r := chi.NewRouter()

	r.Get("/api/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	r.Get("/api/books", func(w http.ResponseWriter, r *http.Request) {
		rows, err := listStmt.Query()
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		defer rows.Close()

		var books []Book
		for rows.Next() {
			var b Book
			rows.Scan(&b.ID, &b.Title, &b.Author, &b.Year)
			books = append(books, b)
		}
		writeJSON(w, http.StatusOK, books)
	})

	r.Get("/api/books/{id}", func(w http.ResponseWriter, r *http.Request) {
		idStr := chi.URLParam(r, "id")
		id, err := strconv.Atoi(idStr)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid id"})
			return
		}

		var b Book
		err = getStmt.QueryRow(id).
			Scan(&b.ID, &b.Title, &b.Author, &b.Year)
		if err == sql.ErrNoRows {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "not found"})
			return
		}
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, b)
	})

	http.ListenAndServe(":8080", r)
}
