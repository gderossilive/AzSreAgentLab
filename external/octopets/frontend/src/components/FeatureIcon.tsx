import React from 'react';
import PawIcon from './PawIcon';

interface FeatureIconProps {
  icon?: React.ReactNode;
  className?: string;
}

const FeatureIcon: React.FC<FeatureIconProps> = ({ 
  icon, 
  className = '' 
}) => {
  return (
    <div className={`feature-icon ${className}`}>
      {icon || <PawIcon width={32} height={32} color="white" />}
    </div>
  );
};

export default FeatureIcon;
