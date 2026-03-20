const { Sequelize, DataTypes } = require('sequelize');
const path = require('path');

const sequelize = new Sequelize({
    dialect: 'sqlite',
    storage: path.join(__dirname, '../../backend/config/database.sqlite'),
    logging: false
});

const Customer = sequelize.define('Customer', {
    company: { type: DataTypes.STRING, unique: true, primaryKey: true },
    address: DataTypes.STRING,
    website: DataTypes.STRING,
    type: DataTypes.STRING,
    category: DataTypes.STRING,
    profile: DataTypes.TEXT,
    coordinates: DataTypes.JSON,
    keyContacts: DataTypes.JSON,
    commonChipPlatforms: DataTypes.JSON,
    products: DataTypes.JSON,
    strategy: DataTypes.TEXT
});

module.exports = { sequelize, Customer };
