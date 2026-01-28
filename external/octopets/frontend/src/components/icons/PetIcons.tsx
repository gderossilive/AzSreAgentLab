import React from 'react';
import PawIcon from '../PawIcon';

interface PetIconProps {
  type?: string;
  className?: string;
  size?: number;
}

export const DogIcon: React.FC<PetIconProps> = ({ className = '', size = 24 }) => (
  <span className={className} style={{ fontSize: `${size/16}rem` }}>🐶</span>
);

export const CatIcon: React.FC<PetIconProps> = ({ className = '', size = 24 }) => (
  <span className={className} style={{ fontSize: `${size/16}rem` }}>😻</span>
);

export const BirdIcon: React.FC<PetIconProps> = ({ className = '', size = 24 }) => (
  <span className={className} style={{ fontSize: `${size/16}rem` }}>🦜</span>
);

export const SmallMammalIcon: React.FC<PetIconProps> = ({ className = '', size = 24 }) => (
  <span className={className} style={{ fontSize: `${size/16}rem` }}>🐹</span>
);

export const OtherPetIcon: React.FC<PetIconProps> = ({ className = '', size = 24 }) => (
  <span className={className} style={{ fontSize: `${size/16}rem` }}>🦔</span>
);

const PetIcon: React.FC<PetIconProps> = ({ type, className = '', size = 24 }) => {
  switch (type) {
    case 'dogs':
      return <DogIcon className={className} size={size} />;
    case 'cats':
      return <CatIcon className={className} size={size} />;
    case 'birds':
      return <BirdIcon className={className} size={size} />;
    case 'small_mammals':
      return <SmallMammalIcon className={className} size={size} />;
    case 'other':
      return <OtherPetIcon className={className} size={size} />;
    default:
      return <PawIcon className={className} width={size} height={size} color="var(--primary-700)" />;
  }
};

export default PetIcon;
