use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::get,
    Json, Router,
};
use r2d2::Pool;
use r2d2_sqlite::SqliteConnectionManager;
use serde::Serialize;

type DbPool = Pool<SqliteConnectionManager>;

#[derive(Serialize)]
struct Book {
    id: u32,
    title: String,
    author: String,
    year: u16,
}

fn init_db(pool: &DbPool) {
    let conn = pool.get().unwrap();
    conn.execute_batch("PRAGMA journal_mode=WAL").unwrap();
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS books (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            author TEXT NOT NULL,
            year INTEGER NOT NULL
        )",
    )
    .unwrap();

    let seeds = [
        (1, "The Rust Programming Language", "Steve Klabnik", 2019),
        (2, "The Go Programming Language", "Alan Donovan", 2015),
        (3, "Designing Data-Intensive Applications", "Martin Kleppmann", 2017),
        (4, "Clean Code", "Robert C. Martin", 2008),
        (5, "Structure and Interpretation of Computer Programs", "Harold Abelson", 1996),
    ];

    let mut stmt = conn
        .prepare("INSERT OR IGNORE INTO books (id, title, author, year) VALUES (?1, ?2, ?3, ?4)")
        .unwrap();
    for (id, title, author, year) in &seeds {
        stmt.execute(rusqlite::params![id, title, author, year])
            .unwrap();
    }
}

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({"status": "ok"}))
}

async fn list_books(State(pool): State<DbPool>) -> Result<Json<Vec<Book>>, StatusCode> {
    let pool = pool.clone();
    tokio::task::spawn_blocking(move || {
        let conn = pool.get().map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        let mut stmt = conn
            .prepare("SELECT id, title, author, year FROM books")
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        let books = stmt
            .query_map([], |row| {
                Ok(Book {
                    id: row.get(0)?,
                    title: row.get(1)?,
                    author: row.get(2)?,
                    year: row.get(3)?,
                })
            })
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        Ok(Json(books))
    })
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
}

async fn get_book(
    State(pool): State<DbPool>,
    Path(id): Path<u32>,
) -> Result<Json<Book>, StatusCode> {
    let pool = pool.clone();
    tokio::task::spawn_blocking(move || {
        let conn = pool.get().map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        conn.query_row(
            "SELECT id, title, author, year FROM books WHERE id = ?1",
            [id],
            |row| {
                Ok(Book {
                    id: row.get(0)?,
                    title: row.get(1)?,
                    author: row.get(2)?,
                    year: row.get(3)?,
                })
            },
        )
        .map(Json)
        .map_err(|_| StatusCode::NOT_FOUND)
    })
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
}

#[tokio::main]
async fn main() {
    let manager = SqliteConnectionManager::file("books.db");
    let pool = Pool::builder().max_size(16).build(manager).unwrap();
    init_db(&pool);

    let app = Router::new()
        .route("/api/health", get(health))
        .route("/api/books", get(list_books))
        .route("/api/books/{id}", get(get_book))
        .with_state(pool);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
