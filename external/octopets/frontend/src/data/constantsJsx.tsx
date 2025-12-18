// Constants with JSX Components
import React from 'react';
import { PetType, ListingType } from '../types/types';
import { DogIcon, CatIcon, BirdIcon, SmallMammalIcon, OtherPetIcon } from '../components/icons/PetIcons';

// Pet types that are supported by the application
export const PET_TYPES: PetType[] = [
  { id: "dogs", name: "Dogs", icon: <DogIcon size={42} />, description: "Man's best friend" },
  { id: "cats", name: "Cats", icon: <CatIcon size={42} />, description: "Independent and loving companions" },
  { id: "birds", name: "Birds", icon: <BirdIcon size={42} />, description: "Colorful, vocal friends" },
  { id: "small_mammals", name: "Mammals", icon: <SmallMammalIcon size={42} />, description: "Hamsters, guinea pigs, rabbits, and more" },
  { id: "other", name: "Other Pets", icon: <OtherPetIcon size={42} />, description: "Reptiles, fish, and more unusual friends" }
];

// Export the constants for use in components
export default {
  PET_TYPES
};