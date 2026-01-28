export interface AppConfig {
    apiUrl: string;
    useMockData: boolean;
}

export const appConfig: AppConfig = {
    apiUrl: '/api', // Use relative path for nginx proxy
    useMockData: process.env.REACT_APP_USE_MOCK_DATA === undefined ? true : process.env.REACT_APP_USE_MOCK_DATA.toLowerCase() === 'true'
};
