const express = require("express");
const cors = require("cors");
const fs = require("fs");

const app = express();
const PORT = 3000;

app.use(cors());
app.use(express.json());

const DB_FILE = "./seed-data.json";

// Read database
function readDB() {
    return JSON.parse(fs.readFileSync(DB_FILE, "utf8"));
}

// Save database
function saveDB(data) {
    fs.writeFileSync(DB_FILE, JSON.stringify(data, null, 2));
}

// GET all products
app.get("/api/products", (req, res) => {
    const db = readDB();
    res.json(db.products);
});

// GET product by id
app.get("/api/products/:id", (req, res) => {
    const db = readDB();
    const product = db.products.find(
        p => p.id == req.params.id
    );

    if (!product)
        return res.status(404).json({
            message: "Product not found"
        });

    res.json(product);
});

// CREATE product
app.post("/api/products", (req, res) => {
    const db = readDB();

    const newProduct = {
        id: Date.now(),
        name: req.body.name,
        price: req.body.price
    };

    db.products.push(newProduct);

    saveDB(db);

    res.status(201).json(newProduct);
});

// DELETE product
app.delete("/api/products/:id", (req, res) => {
    const db = readDB();

    db.products = db.products.filter(
        p => p.id != req.params.id
    );

    saveDB(db);

    res.json({
        message: "Deleted"
    });
});

app.listen(PORT, () => {
    console.log(`Backend running on http://localhost:${PORT}`);
});