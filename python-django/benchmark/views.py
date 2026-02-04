import sqlite3

from django.http import JsonResponse

DB_PATH = "books.db"


def _init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(
        """CREATE TABLE IF NOT EXISTS books (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            author TEXT NOT NULL,
            year INTEGER NOT NULL
        )"""
    )
    seeds = [
        (1, "The Rust Programming Language", "Steve Klabnik", 2019),
        (2, "The Go Programming Language", "Alan Donovan", 2015),
        (3, "Designing Data-Intensive Applications", "Martin Kleppmann", 2017),
        (4, "Clean Code", "Robert C. Martin", 2008),
        (5, "Structure and Interpretation of Computer Programs", "Harold Abelson", 1996),
    ]
    for s in seeds:
        conn.execute(
            "INSERT OR IGNORE INTO books (id, title, author, year) VALUES (?, ?, ?, ?)",
            s,
        )
    conn.commit()
    conn.close()


_init_db()


def health(request):
    return JsonResponse({"status": "ok"})


def list_books(request):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.execute("SELECT id, title, author, year FROM books")
    books = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return JsonResponse(books, safe=False)


def get_book(request, book_id):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.execute(
        "SELECT id, title, author, year FROM books WHERE id = ?", (book_id,)
    )
    row = cursor.fetchone()
    conn.close()
    if row is None:
        return JsonResponse({"error": "not found"}, status=404)
    return JsonResponse(dict(row))
