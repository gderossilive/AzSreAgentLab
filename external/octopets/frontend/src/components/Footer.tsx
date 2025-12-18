import React from "react";
import { Link } from "react-router-dom";
import { ROUTES } from "../data/constants";
import "../styles/Footer.css";

const Footer: React.FC = () => {
  return (
    <footer className="footer">
      <div className="footer-container">
        <div className="footer-content">
          {/* Simplified footer based on Figma design */}
          <div className="footer-logo">
            <span className="logo-text">Octopets</span>
          </div>
          
          <div className="footer-links">
            <Link to={ROUTES.HOME}>Home</Link>
            <Link to={ROUTES.LISTINGS}>Listings</Link>
            <Link to={ROUTES.ADD_LISTING}>Add a Listing</Link>
            <Link to="#">About Us</Link>
            <Link to="#">Contact</Link>
          </div>
          
          <div className="footer-social">
            <a href="#" target="_blank" rel="noopener noreferrer">Instagram</a>
            <a href="#" target="_blank" rel="noopener noreferrer">Twitter</a>
            <a href="#" target="_blank" rel="noopener noreferrer">Facebook</a>
          </div>
        </div>
        
        <div className="footer-bottom">
          <p>&copy; {new Date().getFullYear()} Octopets. All rights reserved.</p>
        </div>
      </div>
    </footer>
  );
};

export default Footer;
