import puppeteer from 'puppeteer';

class LoginAutomation {
    constructor() {
        this.browser = null;
        this.page = null;
    }

    async initialize() {
        this.browser = await puppeteer.launch({
            headless: false,
            defaultViewport: null,
            args: ['--start-maximized', '--no-sandbox']
        });
        this.page = await this.browser.newPage();
        
        // Add request/response logging
        this.page.on('request', request => {
            console.log('Request:', request.method(), request.url());
        });
        this.page.on('response', response => {
            console.log('Response:', response.status(), response.url());
        });
    }

    async openLoginPage(loginUrl) {
        try {
            if (!this.browser) {
                await this.initialize();
            }

            console.log('Navigating to login page:', loginUrl);
            await this.page.goto(loginUrl, { waitUntil: 'networkidle0', timeout: 600000 });

            console.log('Login page opened. Browser will remain open for manual interaction.');
            console.log('Call close() method when you want to close the browser.');

            return true;
        } catch (error) {
            console.error('Failed to open login page:', error);
            return false;
        }
    }

    async close() {
        if (this.browser) {
            await this.browser.close();
            this.browser = null;
            this.page = null;
        }
    }
}

export default LoginAutomation; 