package benchmark;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.sqlite.SQLiteDataSource;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/api")
@Produces(MediaType.APPLICATION_JSON)
public class BookResource {

    private static final SQLiteDataSource ds;

    static {
        ds = new SQLiteDataSource();
        ds.setUrl("jdbc:sqlite:books.db");

        try (Connection conn = ds.getConnection(); Statement stmt = conn.createStatement()) {
            stmt.execute("PRAGMA journal_mode=WAL");
            stmt.execute("""
                CREATE TABLE IF NOT EXISTS books (
                    id INTEGER PRIMARY KEY,
                    title TEXT NOT NULL,
                    author TEXT NOT NULL,
                    year INTEGER NOT NULL
                )""");

            try (PreparedStatement ps = conn.prepareStatement(
                    "INSERT OR IGNORE INTO books (id, title, author, year) VALUES (?, ?, ?, ?)")) {
                Object[][] seeds = {
                    {1, "The Rust Programming Language", "Steve Klabnik", 2019},
                    {2, "The Go Programming Language", "Alan Donovan", 2015},
                    {3, "Designing Data-Intensive Applications", "Martin Kleppmann", 2017},
                    {4, "Clean Code", "Robert C. Martin", 2008},
                    {5, "Structure and Interpretation of Computer Programs", "Harold Abelson", 1996},
                };
                for (Object[] s : seeds) {
                    ps.setInt(1, (int) s[0]);
                    ps.setString(2, (String) s[1]);
                    ps.setString(3, (String) s[2]);
                    ps.setInt(4, (int) s[3]);
                    ps.executeUpdate();
                }
            }
        } catch (Exception e) {
            throw new RuntimeException("Failed to initialize database", e);
        }
    }

    @GET
    @Path("/health")
    public Map<String, String> health() {
        return Map.of("status", "ok");
    }

    @GET
    @Path("/books")
    public List<Book> listBooks() throws Exception {
        List<Book> books = new ArrayList<>();
        try (Connection conn = ds.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT id, title, author, year FROM books")) {
            while (rs.next()) {
                books.add(new Book(rs.getInt(1), rs.getString(2), rs.getString(3), rs.getInt(4)));
            }
        }
        return books;
    }

    @GET
    @Path("/books/{id}")
    public Response getBook(@PathParam("id") int id) throws Exception {
        try (Connection conn = ds.getConnection();
             PreparedStatement ps = conn.prepareStatement(
                 "SELECT id, title, author, year FROM books WHERE id = ?")) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return Response.ok(new Book(rs.getInt(1), rs.getString(2), rs.getString(3), rs.getInt(4))).build();
                }
            }
        }
        return Response.status(Response.Status.NOT_FOUND).entity(Map.of("error", "not found")).build();
    }
}
