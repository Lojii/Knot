import Foundation

enum DashboardHTML {

    static let page: String = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Knot Dashboard</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 2rem; background: #f5f5f7; color: #1d1d1f; }
            h1 { font-size: 1.5rem; }
            .status { padding: 1rem; background: #fff; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        </style>
    </head>
    <body>
        <h1>Knot Dashboard</h1>
        <div class="status">
            <p>Web service is running.</p>
        </div>
    </body>
    </html>
    """
}
