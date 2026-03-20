const express = require('express');
const multer = require('multer');
const fs = require('fs');
const router = express.Router();

const { searchLead, proxyImage } = require('../controllers/searchController');
const { getConfig, saveConfig, testConfig } = require('../controllers/configController');
const { translatePdf } = require('../controllers/pdfController');
const { getCustomers, saveCustomer, deleteCustomer } = require('../controllers/customerController');

const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        const dir = '/tmp/pdf_uploads/';
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        cb(null, dir);
    },
    filename: (req, file, cb) => cb(null, Date.now() + '.pdf')
});
const upload = multer({ storage, limits: { fileSize: 200 * 1024 * 1024 } });

router.post('/search', searchLead);
router.get('/config', getConfig);
router.post('/config', saveConfig);
router.get('/config/test', testConfig);
router.get('/image-proxy', proxyImage);
router.post('/translate-pdf', upload.single('file'), translatePdf);

// CRM 路由群
router.get('/customers', getCustomers);
router.post('/customers', saveCustomer);
router.delete('/customers', deleteCustomer); // 挂载删除路由

module.exports = router;
