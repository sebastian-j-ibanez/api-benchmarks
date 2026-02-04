from django.urls import path

from benchmark import views

urlpatterns = [
    path("api/health", views.health),
    path("api/books", views.list_books),
    path("api/books/<int:book_id>", views.get_book),
]
