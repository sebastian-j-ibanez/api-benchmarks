import { Database } from "bun:sqlite";
import { cpus } from "os";

if (!process.env.BUN_WORKER) {
  const db = new Database("books.db");
  db.exec("PRAGMA journal_mode=WAL");
  db.exec(`CREATE TABLE IF NOT EXISTS books (
      id INTEGER PRIMARY KEY,
      title TEXT NOT NULL,
      author TEXT NOT NULL,
      year INTEGER NOT NULL
  )`);
  const seedStmt = db.prepare(
    "INSERT OR IGNORE INTO books (id, title, author, year) VALUES (?, ?, ?, ?)"
  );
  const seeds = [
    [1, "The Rust Programming Language", "Steve Klabnik", 2019],
    [2, "The Go Programming Language", "Alan Donovan", 2015],
    [3, "Designing Data-Intensive Applications", "Martin Kleppmann", 2017],
    [4, "Clean Code", "Robert C. Martin", 2008],
    [5, "Structure and Interpretation of Computer Programs", "Harold Abelson", 1996],
  ];
  for (const s of seeds) {
    seedStmt.run(...s);
  }
  db.close();

  const numCPUs = cpus().length;
  const children = [];
  for (let i = 0; i < numCPUs; i++) {
    children.push(
      Bun.spawn(["bun", import.meta.filename], {
        env: { ...process.env, BUN_WORKER: "1" },
        stdio: ["inherit", "inherit", "inherit"],
      })
    );
  }
  const shutdown = () => {
    for (const child of children) child.kill(9);
    process.exit(0);
  };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
  await new Promise(() => {});
}

const db = new Database("books.db", { readonly: true });
const listStmt = db.prepare("SELECT id, title, author, year FROM books");
const getStmt = db.prepare("SELECT id, title, author, year FROM books WHERE id = ?");

const healthBody = JSON.stringify({ status: "ok" });
const notFoundBody = JSON.stringify({ error: "not found" });
const jsonHeaders = { "Content-Type": "application/json" };

Bun.serve({
  port: 8080,
  reusePort: true,
  fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;

    if (path === "/api/health") {
      return new Response(healthBody, { headers: jsonHeaders });
    }

    if (path === "/api/books") {
      return new Response(JSON.stringify(listStmt.all()), {
        headers: jsonHeaders,
      });
    }

    if (path.startsWith("/api/books/")) {
      const id = parseInt(path.substring(11), 10);
      if (isNaN(id)) {
        return new Response(JSON.stringify({ error: "invalid id" }), {
          status: 400,
          headers: jsonHeaders,
        });
      }
      const book = getStmt.get(id);
      if (!book) {
        return new Response(notFoundBody, {
          status: 404,
          headers: jsonHeaders,
        });
      }
      return new Response(JSON.stringify(book), { headers: jsonHeaders });
    }

    return new Response("Not Found", { status: 404 });
  },
});
