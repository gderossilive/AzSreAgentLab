import React from 'react';
import { PET_TYPES } from '../data/constantsJsx';
import '../styles/FloatingPetIcons.css';

// Interface for the props
interface FloatingPetIconsProps {
  count?: number;
}

const FloatingPetIcons: React.FC<FloatingPetIconsProps> = ({ count = 12 }) => {
  // Generate an array of random pet icons
  const generatePetIcons = () => {
    const icons = [];
    for (let i = 0; i < count; i++) {
      // Get a random pet type
      const randomPet = PET_TYPES[Math.floor(Math.random() * PET_TYPES.length)];
      
      // Create random positions and animations
      const randomSize = Math.random() * 0.7 + 0.6; // Size between 0.6 and 1.3
      const randomX = Math.random() * 100; // X position between 0 and 100%
      const randomY = Math.random() * 100; // Y position between 0 and 100%
      const randomDelay = Math.random() * 20; // Delay between 0 and 20s
      const randomDuration = Math.random() * 10 + 10; // Duration between 10 and 20s
      const randomOpacity = Math.random() * 0.5 + 0.3; // Opacity between 0.3 and 0.8
      
      icons.push(
        <div
          key={i}
          className="floating-pet-icon"
          style={{
            position: 'absolute',
            left: `${randomX}%`,
            top: `${randomY}%`,
            transform: `scale(${randomSize})`,
            opacity: randomOpacity,
            animationDelay: `${randomDelay}s`,
            animationDuration: `${randomDuration}s`,
          }}
        >
          {randomPet.icon}
        </div>
      );
    }
    return icons;
  };

  return <div className="floating-pet-icons-container">{generatePetIcons()}</div>;
};

export default FloatingPetIcons;
