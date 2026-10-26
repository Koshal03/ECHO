package com.koshal.echotalk.network

import com.koshal.echotalk.data.model.ConfigResponse
import com.google.gson.JsonObject
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST

interface EchoApiService {

    @GET("/api/config")
    suspend fun getConfig(): Response<ConfigResponse>

    @POST("/api/guest/init")
    suspend fun initGuest(@Body body: Map<String, String>): Response<JsonObject>

    @POST("/api/auth/send-otp")
    suspend fun sendOtp(@Body body: Map<String, String>): Response<JsonObject>

    @POST("/api/auth/verify-otp")
    suspend fun verifyOtp(@Body body: Map<String, String>): Response<JsonObject>

    @POST("/api/auth/check-username")
    suspend fun checkUsername(@Body body: Map<String, String>): Response<JsonObject>

    @POST("/api/auth/register")
    suspend fun register(@Body body: Map<String, String>): Response<JsonObject>

    @POST("/api/user/delete-account")
    suspend fun deleteAccount(@Body body: Map<String, String>): Response<JsonObject>

    @POST("/api/safety/report")
    suspend fun submitReport(@Body body: Map<String, String>): Response<JsonObject>

    @POST("/api/safety/block")
    suspend fun blockUser(@Body body: Map<String, String>): Response<JsonObject>

    @POST("/api/wallet/purchase")
    suspend fun purchasePack(@Body body: Map<String, String>): Response<JsonObject>

    @POST("/api/wallet/rewarded-ad-grant")
    suspend fun grantRewardedAdCoins(@Body body: Map<String, String>): Response<JsonObject>

    companion object {
        // Default to local emulator (10.0.2.2:5000) or replace with LAN IP/cloud URL
        var BASE_URL = "http://10.0.2.2:5000"

        fun create(baseUrl: String = BASE_URL): EchoApiService {
            return Retrofit.Builder()
                .baseUrl(baseUrl)
                .addConverterFactory(GsonConverterFactory.create())
                .build()
                .create(EchoApiService::class.java)
        }
    }
}
