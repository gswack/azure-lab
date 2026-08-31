const express = require("express");
const { execFile } = require("child_process");
const path = require("path");

const app = express();
const PORT = 3000;

// Private backend servers
const PRIVATE_APIS = [
    "http://10.0.0.132:3000",
    "http://10.0.0.133:3000"
];

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// Pick a random private backend
function getRandomPrivateApi() {
    const index = Math.floor(Math.random() * PRIVATE_APIS.length);
    return PRIVATE_APIS[index];
}


// =====================================================
// GET PRODUCTS
// =====================================================

app.get("/api/products", (req, res) => {

    const PRIVATE_API = getRandomPrivateApi();

    console.log(`🔀 Sending GET request to ${PRIVATE_API}`);

    execFile(
        "curl",
        [
            "-s",
            "--max-time",
            "10",
            `${PRIVATE_API}/api/products`
        ],
        (error, stdout, stderr) => {

            if (error) {
                console.error(`❌ Curl error connecting to ${PRIVATE_API}:`, error.message);
                console.error(stderr);

                return res.status(500).json({
                    message: "Cannot connect to private backend",
                    backend: PRIVATE_API
                });
            }

            try {

                const products = JSON.parse(stdout);

                console.log(`✅ Products received from ${PRIVATE_API}`);

                res.json(products);

            } catch (err) {

                console.error("❌ Invalid JSON:", err.message);
                console.error("Backend response:", stdout);

                res.status(500).json({
                    message: "Invalid response from backend",
                    backend: PRIVATE_API
                });
            }
        }
    );
});


// =====================================================
// DELETE PRODUCT
// =====================================================

app.delete("/api/products/:id", (req, res) => {

    const productId = req.params.id;
    const PRIVATE_API = getRandomPrivateApi();

    console.log(
        `🗑️ Deleting product ${productId} from ${PRIVATE_API}...`
    );

    execFile(
        "curl",
        [
            "-s",
            "-X",
            "DELETE",
            "--max-time",
            "10",
            `${PRIVATE_API}/api/products/${productId}`
        ],
        (error, stdout, stderr) => {

            if (error) {

                console.error(
                    `❌ Curl error connecting to ${PRIVATE_API}:`,
                    error.message
                );

                console.error(stderr);

                return res.status(500).json({
                    message: "Cannot connect to private backend",
                    backend: PRIVATE_API
                });
            }

            console.log(`✅ Backend response from ${PRIVATE_API}:`, stdout);

            try {

                const result = JSON.parse(stdout);

                res.json(result);

            } catch (err) {

                console.error("❌ Invalid backend response:", stdout);

                res.status(500).json({
                    message: "Invalid response from backend",
                    response: stdout,
                    backend: PRIVATE_API
                });
            }
        }
    );
});


// =====================================================
// START SERVER
// =====================================================

app.listen(PORT, "0.0.0.0", () => {
    console.log(`🌐 Frontend server running on port ${PORT}`);
    console.log("🔀 Available private backends:");

    PRIVATE_APIS.forEach(api => {
        console.log(`   - ${api}`);
    });
});