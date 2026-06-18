import Foundation
import SwiftUI

struct AppConfig {
    // Supabase Core Configuration (Manual V2)
    static let supabaseProjectID = "tzxuxjxllbgiffhtwytx"
    static let supabaseURL = URL(string: "https://tzxuxjxllbgiffhtwytx.supabase.co")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR6eHV4anhsbGJnaWZmaHR3eXR4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMwMTM2OTEsImV4cCI6MjA3ODU4OTY5MX0.5iQaBQXcdcbfE8gTcu-yNIJN9vaqBomuBaPC62rtRMY"
    
    // UI/Web Configuration
    static let webAppURL = URL(string: "https://cliniboss.vercel.app/")!
    
    // Core Palette
    static let cliniBossPrimary = Color(red: 48/255, green: 179/255, blue: 162/255)
}
