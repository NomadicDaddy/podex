DROP TABLE IF EXISTS "items";

CREATE TABLE "items" (
	"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
	"item" TEXT NOT NULL,
	"description" TEXT NOT NULL,
	"created_at" DATETIME DEFAULT CURRENT_TIMESTAMP,
	"updated_at" DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO
	"items" ("item", "description")
VALUES
	('Item 1', 'Description for item 1'),
	('Item 2', 'Description for item 2'),
	('Item 3', 'Description for item 3'),
	('Item 4', 'Description for item 4'),
	('Item 5', 'Description for item 5'),
	('Item 6', 'Description for item 6'),
	('Item 7', 'Description for item 7'),
	('Item 8', 'Description for item 8'),
	('Item 9', 'Description for item 9'),
	('Item 10', 'Description for item 10'),
	('Item 11', 'Description for item 11'),
	('Item 12', 'Description for item 12'),
	('Item 13', 'Description for item 13'),
	('Item 14', 'Description for item 14'),
	('Item 15', 'Description for item 15'),
	('Item 16', 'Description for item 16'),
	('Item 17', 'Description for item 17'),
	('Item 18', 'Description for item 18'),
	('Item 19', 'Description for item 19'),
	('Item 20', 'Description for item 20'),
	('Item 21', 'Description for item 21'),
	('Item 22', 'Description for item 22'),
	('Item 23', 'Description for item 23'),
	('Item 24', 'Description for item 24'),
	('Item 25', 'Description for item 25'),
	('Item 26', 'Description for item 26'),
	('Item 27', 'Description for item 27'),
	('Item 28', 'Description for item 28'),
	('Item 29', 'Description for item 29'),
	('Item 30', 'Description for item 30'),
	('Item 31', 'Description for item 31'),
	('Item 32', 'Description for item 32'),
	('Item 33', 'Description for item 33'),
	('Item 34', 'Description for item 34'),
	('Item 35', 'Description for item 35');
