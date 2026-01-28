import React from 'react';
import { Link, NavLink } from 'react-router-dom';
import { ROUTES } from '../data/constants';
import '../styles/Navbar.css';

const Navbar: React.FC = () => {
  return (
    <nav className="navbar">
      <div className="navbar-container">          
        <div className="navbar-left">
          <Link to={ROUTES.HOME} className="navbar-logo">
            <span className="logo-text">Octopets</span>
          </Link>
          
          <ul className="nav-menu">
            <li className="nav-item">
              <NavLink 
                to={ROUTES.LISTINGS} 
                className={({ isActive }) => isActive ? 'nav-link active' : 'nav-link'}
              >
                Listings
              </NavLink>
            </li>
          </ul>
        </div>
        
        <div className="navbar-right">
          <Link to="#" className="nav-link">Log in</Link>
          <Link to="#" className="btn btn-primary">Sign up</Link>
        </div>
      </div>
    </nav>
  );
};

export default Navbar;