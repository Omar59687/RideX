![Image](documents\pdf to md\images\Project 1 final version-4_artifacts\image_000000_cb2139936c159ae2368dfc8e571a44f7855e644446d7a999f84c46c575665117.png)

## The Hashemite University, Zarqa, Jordan Faculty of Prince Al-Hussein Bin Abdallah II for Information Technology Software Engineering Department

## RideX

A project submitted in partial fulfillment of the requirements for the B.Sc. Degree in Software Engineering

By

Sanad Khaled Silme (2332711) Yousuf Ahmad Aljabari (2334160) Moath Abd Salam Bani Fadel (2334657) Omar Ahmad Khalil (2334447)

## Supervised by

Dr. Bashar Abdul Kareem Al Shboul

## Committee Member Names

First Committee Member's First Name Middle Initial Last Name Second Committee Member's First Name Middle Initial Last Name

Semester Year

Second Semester 2025/2026

## ABSTRACT

RideX is a smart ride -hailing application designed to address the challenges of finding reliable, efficient, and accessible transportation services. Many users experience difficulties with traditional transportation methods due to long waiting times, lack of price transparency, and limited trip management options. To overcome these challenges, RideX provides a mobile-based platform that connects riders with drivers using GPS technology, real-time tracking, and secure payment options.

The system was designed and analyzed using software engineering methodologies, including requirements engineering, UML modeling, database design, and system architecture planning. The proposed solution supports essential ridebooking functionalities such as user authentication, location selection, fare estimation, trip tracking, and an integrated help center. In addition, RideX introduces a multi-stop trip feature that allows users to add multiple destinations within a single ride.

The expected outcome is a user-friendly and efficient transportation platform that improves mobility, enhances user convenience, and increases transparency throughout the ride-booking process. The project contributes to the development of modern transportation solutions by providing a scalable and flexible platform capable of supporting future enhancements and additional services.



## ABBREVIATIONS

| GPS    | Global Positioning System    |
|--------|------------------------------|
| UI     | User Interface               |
| OS     | Operating System             |
| iOS    | iPhone Operating System      |
| DB     | Database                     |
| RAM    | Random Access Memory         |
| FR     | Functional Requirement       |
| NFR    | Non - Functional Requirement |



## 1.1 Overview

The RideX project is a smart mobile-based transportation system designed to connect users with available drivers quickly and efficiently through a mobile application. The system utilizes GPS technology to determine the user's current location and display nearby drivers, helping to reduce waiting time and improve the overall travel experience.

The application allows users to request rides, select the type of vehicle, and view the estimated trip cost before confirming the request. In addition, it provides real -time tracking of the driver to ensure safety and transparency during the trip.

RideX aims to offer a modern, reliable, and user -friendly alternative to traditional transportation methods, especially for individuals who do not have access to private vehicles or require convenient and timely transportation services.

## 1.2 Project Motivation

RideX is smart transportation platform that connects users with available drivers through a mobile application using GPS, providing transparent pricing and real-time tracking, to deliver a safe, fast, and organized travel experience.

RideX will have a strong positive impact on users and encourage a large segment of society due to following benefits:

A -Easy access to transportation without long waiting time.

B -Monitor the driver location and estimated arrival.

C -Known price of trip before confirming the trip.

D -Support people who lack vehicles or have mobility limitations.

E -More affordable , comfortable , safer compared with traditional transports.

The product will help its manufacturers achieve number of goals , including:

## CHAPTER 1: INTRODUCTION

A

-

B

-

The strongest among competitors how is offer transportation options.

Meeting societal needs by provide an efficient mobility solution.

C

-

Improve customer satisfaction with a modern and accessible service

1.3 Problem Statement

Many people struggle with finding reliable transportation options , which often

causes delay and effects their daily schedules , this issue become even more critical for

elderly , people with medical conditions , or users who value time sensitivity.

Additionally, traditional transportation methods often lack transparency in

pricing, real-time tracking, and reliability, making them less efficient and less

convenient for users.

1.4 Project Aim and Objectives

Goal 1: Meet the needs of society

Objectives:

A. Enable users to find a car without leaving their home.

B. Support elderly people and individuals with disabilities or medical conditions

by providing easier access to transportation.

Goal 2: Increase user satisfaction

Objectives:

A. Allow users to request a trip anytime and from anywhere.

B. Provide a fare estimation before starting the trip.

C. Increase the number of available drivers to reduce waiting time.

Goal 3: Support digital transformation in transportation

Objectives:

A. Provide a fully online and accessible mobile application that facilitates

digital mobility services.

.

Goal 4: Provide safe and reliable transportation

Objectives:

- A. Offer real -time trip tracking for user safety.
- B. Allow users to know the driver's identity and vehicle information before starting the trip.

Goal 5: Expand RideX coverage area

Objectives:

- A. Increase the number of cities supported by RideX.
- B. Increase the number of available drivers.

Goal 6: Become a leading transportation service

Objectives:

- A. Environmental protection by encouraging the use of electric vehicles.
- B. Improve customer comfort and travel experience.

## 1.5 Project Scope

- A) Product Scope
2. -users can do: -
3. A.Registration
- B. Login/Logout
- C. View Profile
- D. Update Info
- E. View Notifications
- F. View Estimated Price
- G. Get Help
- H. Select Payment Method
- I. View Driver Location
- J. Determine Current Location
- K. Destination Selection
- L. Choose Type of Car
- M. Select Multi -Stop Point
- N. View Rider Location
- O. Request Trip
- P. Complete Trip
- Q. Set Availability Status
- R. View User Issues
- S. Access User &amp; Driver Trips
- T. Review Captain Applications
- U. Block/Unblock Account
- B) Project Scope
- A. Acceptance Criteria
26. A -Driver must be found within 30 seconds
27. B -Driver arrival time should be less than 7 minutes
28. C -Driver movement must appear on the map
29. D -Estimated price must be displayed before confirming the trip
- B. Deliverables
31. A -

Mobile Application

- B -Database containing information about users
- C -AI Tools to get quick assistance

D -GPS

## E -Documentation

- C) Responsibilities
- B. Mobile App Developer

## Responsibilities:

- 1 -Implementing user interface
- 2 -Bug fixing
- 3 -Improving application features

## C. Backend Developer

## Responsibilities:

- 1 -Handling requests and data processing
- 2 -Integration of services
- 3 -Securing data
- D. Database Engineer

## Responsibilities:

- 1 -Designing database structure
- 2 -Storing data
- 3 -Optimizing performance and backups

## E.QA Engineer

## Responsibilities:

- 1 -Tracking bugs
- 2 -Integration testing
- 3 -Ensuring application meets requirements

## 1.5.1. Project Software and Hardware Requirements

- A) Software Requirements:
1. Mobile Application
- Operating Systems:
4. o Android
5. o iOS
- Development Tools:
7. o Flutter SDK
8. o Android Studio
9. o Visual Studio Code (Optional)
- Programming Language:
11. o Dart
- Frameworks &amp; Libraries:
13. o Flutter Framework
14. o Google Maps Flutter Package
15. o Firebase SDK
16. o Payment Gateway SDK
17. o Geolocator Package
2. External Services
- GPS / Location Service (Google Maps API)
- Payment Gateway (Stripe / PayPal / Local Bank API)
- B) Hardware Requirement:
22. 1 -Smartphone with:
23. o Minimum 2GB RAM
24. o Minimum 16GB Storage
25. o GPS enabled
26. o Internet connectivity

## 1.6 Project Limitations

## Limitation:

- A -The system is limited to ride-booking services only (Rider, Driver, Admin)
- B -The application will be developed for mobile platforms only (Android and iOS)
- C -The system depends on third-party services such as:
- GPS / Maps services
- Payment gateway

## Project Exclusions:

- A -Food or package delivery services
- B -Coverage outside the primary city
- C -Multi -language support
- D -Autonomous vehicle integration

## 1.7 Project Expected Output

The system will enable users to connect with nearby drivers, view estimated trip costs, and track their rides in real time.

The application aims to reduce waiting time, improve user convenience, and provide a safe and reliable transportation experience. Additionally, it is expected to enhance accessibility for users who do not have private vehicles .

## 1.8 Project Schedule

| Activity                                             | Resources                              | Duration    | Dependencies    | Constraints      |
|------------------------------------------------------|----------------------------------------|-------------|-----------------|------------------|
| User  Authentication  (Registration,  Login, Logout) | Mobile  Developer,  Backend  Developer | 3 weeks     | -----           | Time  Limitation |

| Settings &  Profile (Edit  profile,  Language  selection)                               | Mobile  Developer                      | 2 weeks    | User  Authentication        | Resource  Availability             |
|-----------------------------------------------------------------------------------------|----------------------------------------|------------|-----------------------------|------------------------------------|
| Trip  Management  (Choose car type,  Price estimation,  Confirm trip)                   | Mobile  Developer,  Backend  Developer | 4 weeks    | User  Authentication        | GPS  Limitations                   |
| Store User  Information                                                                 | Backend  Developer, Database Eng       | 2 weeks    | User  Authentication        | Data  Consistency                  |
| Store Trip  Records                                                                     | Backend  Developer, Database Eng       | 2 weeks    | Trip  Management            | Task  Dependency                   |
| Help Center  (Display help  topics)                                                     | Mobile  Developer                      | 1 weeks    | -----                       | Time  Limitation, Limited  Content |
| Chatbot Support                                                                         | Backend  Developer, Database Eng       | 2 weeks    | Help Center                 | Backend  Capability                |
| Determine  Current Location                                                             | Mobile  Developer,  Backend  Developer | 2 weeks    | Trip  Management            | GPS  Accuracy                      |
| Destination  Selection                                                                  | Mobile  Developer, Backend Developer   | 1 weeks    | Determine  Current Location | GPS  Accuracy                      |
| Real - Time Trip  Tracking  (Update driver  location, display  driver movement  on map) | Mobile  Developer,  Backend  Developer | 3 weeks    | Destination  Selection      | GPS  Integration                   |

## 1.9 Project, product, and schedule risks

## A) GPS Integration Failure

Category: Technical

Analysis: Tracking may be inaccurate or incorrect

Strategy: Mitigate

Early testing of GPS integration

Prepare an alternative tracking plan

- B) Resource Shortage
- D) App Store Approval Delay

Category: Organizational

Analysis: Late development or missed deadlines

Strategy: Transfer

Reassign tasks to another team member or outsource if needed

Category: External

Analysis: Delay in application deployment

Strategy: Accept

App store decisions are outside project control

E) Scope Creep

Category: Project Management

Analysis: Increased project time and cost

Strategy: Avoid

Prevent unauthorized changes

Enforce change control standards

## F) Unclear Requirements

Category: Project Management

Analysis: Rework and project delays

Strategy: Research

Conduct additional requirement analysis sessions with stakeholders

- G) Task Delay Due to Dependencies

Category: Schedule

Analysis: Delay in one task may affect subsequent tasks

Strategy: Mitigate

Identify critical path

Allow parallel execution where possible

- H) Underestimation of Task Duration

Category: Schedule

Analysis: Tasks may take longer than planned

Strategy: Mitigate

Use realistic estimation techniques

Add buffer time

## 1.10 Report Organization

The remainder of this report is organized as follows. Chapter 2 presents the literature review and analyzes existing transportation applications and related solutions. Chapter 3 describes the requirements engineering and analysis process, including stakeholder identification, functional requirements, and non-functional requirements. Chapter 4 presents the system architecture and design, including UML diagrams, database design, and user interface prototypes. Chapter 5 outlines the implementation plan and development approach of the system. Chapter 6 presents the testing plan, including testing strategies and test cases used to validate the system. Finally, Chapter7

summarizes the project results, discusses the achieved objectives, and provides recommendations for future work.

## 2.1 Introduction

This chapter presents a review of existing ride-hailing and transportation applications related to the proposed RideX system. The purpose of this review is to analyze current solutions, identify their strengths and weaknesses, and understand the features they provide to users. A comparative analysis of several existing applications is presented to highlight the gaps and limitations that motivate the development of the proposed system. Finally, the chapter introduces the overall solution approach and explains how RideX improves upon existing solutions by providing features such as multi -stop trip support, real-time tracking, transparent pricing, and an integrated help center.

## 2.2 Comparing Table

| Existing System                                                                                                                                                              | Strengths                                                                                                                | Weaknesses   |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------|--------------|
| • Available in many  countries worldwide. • High reliability and fast  driver matching.                                                                                      | • Support for local payment  methods can be limited in some  regions. • Very high prices during peak  times.             | Uber         |
| • Very popular in the Middle  East and Jordan. • Offers multiple services,  including ride-hailing, food  delivery, and digital  payments. • Offers a good rewards  program. | • Customer support response can be  slow. • Map routing in some local areas is  sometimes inaccurate.                    | Careem       |
| • A local Jordanian app that  understands the local market  well .                                                                                                           | • Smaller number of cars available  compared to competitors. • The application sometimes  experiences technical crashes. | Petra Ride   |

## CHAPTER 2: LITERATURE REVIEW

|       | • Connects users directly  with licensed yellow taxis.                                                                                          |                                                                                                                                                                   |
|-------|-------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| TaxiF | • A Jordanian ride - hailing  app that is growing in  popularity locally. • Offers competitive pricing  compared to international  competitors. | • Limited brand recognition outside  of major cities. • Fewer features compared to  international apps (e.g., no food  delivery or advanced scheduling  options). |

## 2.3 Overall Solution Approach

The proposed system, RideX, adopts a modern and integrated approach to improve existing transportation solutions by addressing their limitations and enhancing user experience.

Unlike traditional transportation methods, which often lack reliability, transparency, and real-time communication, RideX provides a fully digital platform that connects passengers and drivers efficiently through a mobile application.

The system improves upon prior solutions in several ways:

- 1 -Real -Time Tracking: Enables users to monitor driver location using GPS, improving safety and reducing uncertainty.
- 2 -Transparent Pricing: Provides estimated trip costs before confirmation, eliminating price ambiguity common in traditional transport.
- 3 -Efficient Matching System: Connects users with the nearest available drivers quickly, reducing waiting time.
- 4 -Multi -Stop Trip Support: Allows users to add multiple destinations within a single trip, improving convenience and flexibility compared to basic single-destination systems.

5 -Integrated Payment System: Supports multiple payment methods, making transactions easier and more secure .

## CHAPTER 3: REQUIREMENT ENGINEERING AND ANALYSIS

## 3.1 Stakeholders

Figure 1: Stakeholder Diagram

![Image](output\Project 1 final version-4_artifacts\image_000001_fc71adcbc3ab4a3e1889386b42d59458244c8cb6c6ea203998b0239732ccf20f.png)

## Stakeholders Description

| Stakeholder     | Primary/Secondary Key    | Description                                                                                   |
|-----------------|--------------------------|-----------------------------------------------------------------------------------------------|
| Rider           | Primary Key              | The main users of the  system who request rides  and use the application  services.           |
| Driver          | Primary Key              | Provide transportation  services and interact with  the system to accept and  complete trips. |
| Admin           | Primary Key              | Manage System                                                                                 |
| Payment Gateway | Secondary Key            | Handle financial  transactions securely  between users and the  system.                       |
| GPS System      | Secondary Key            | Provide location tracking  and mapping services  required for the application.                |
| Project Team    | Primary Key              | Responsible for designing,  developing, testing, and  delivering the system.                  |

## 3.2 Use Case Diagram

Figure 2: Use case diagram

![Image](output\Project 1 final version-4_artifacts\image_000002_ad5c3434cac6c20aa7c20468e48914af839da5f1ac7000738546e59ea56ebafd.png)

| Use Case       | Select Payment Method                                                                                                                                                                                                                                    |
|----------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Actors         | Rider, Payment Gateway                                                                                                                                                                                                                                   |
| Preconditions  | Trip is requested                                                                                                                                                                                                                                        |
| Normal Flow    | 1.  The user selects the  preferred payment method (Cash  or Card).  2.  If the user selects Card ,  the system sends the payment  request to the payment gateway.  3.  The payment gateway  processes the transaction and  confirms the payment status. |
| Postcondition  | Payment method is confirmed                                                                                                                                                                                                                              |
| Alternate Flow | ---                                                                                                                                                                                                                                                      |

| Use Case       | Select Multi - Stop Location                                                       |
|----------------|------------------------------------------------------------------------------------|
| Actors         | Rider                                                                              |
| Preconditions  | Select location                                                                    |
| Normal Flow    | 1.  Enter pickup location  2.  (Include)multiple stop  Trip  3.  final destination |
| Postcondition  | Multiple stop points and final destination  are saved                              |
| Alternate Flow | User exceeds maximum allowed stops                                                 |

| Use Case      | Login                                                                                                                                                                                                                                                                                                                           |
|---------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Actors        | User                                                                                                                                                                                                                                                                                                                            |
| Preconditions | Registration                                                                                                                                                                                                                                                                                                                    |
| Normal Flow   | 1.  The user opens the  login screen.  2.  The user enters email  and password.  3.  The system sends the  entered data to System  Verification (Include) .  4.  The system validates  the credentials.  5.  If the credentials are  correct, the user is  authenticated.  6.  The system redirects  the user to the home page. |

| Postcondition    | The user is successfully logged into the  system   |
|------------------|----------------------------------------------------|
| Alternate Flow   | Invalid Account                                    |

## 3.3 Non -Functional User Requirements

## 1. Execution

- A -Usability
- -The system shall provide a simple and user-friendly interface.
- -Users should be able to complete a ride booking within 3–5 steps.

## B -Performance

- -The system shall respond to user actions within 2 seconds.
- -Real -time tracking updates shall be refreshed every few seconds.

## C -Security

- -The system shall ensure secure authentication using encrypted credentials.

## 2. Evolution

- A -Maintainability
- -The system shall be modular to allow easy updates and bug fixes.
- -Code shall follow standard development practices and documentation.

## B -Scalability

- -The system shall support increasing numbers of users and trips without performance degradation.
- -The system shall be deployable on scalable cloud infrastructure.

## 4.1 Overview

This chapter presents the architecture and design of the RideX system. It describes the overall structure of the system and the interaction between its major components. The chapter includes the software architecture views, UML diagrams, database design, state transition diagrams, and user interface prototypes. These design artifacts provide a clear representation of the system functionality and serve as a blueprint for the implementation phase.

## 4.2 Software Architecture

## 4.2.1 Logical view

Figure 3: Abstract level class diagram

![Image](output\Project 1 final version-4_artifacts\image_000003_b72e88623d2eb1088c52fd119446797fa6e6f26c71f4325a6ed6733822851d29.png)

## 4.2.2 Process view

Figure 4: Communication diagram

![Image](output\Project 1 final version-4_artifacts\image_000004_396db7f4f6f785804518c195258602f15b6cfd050150cc4f5362809fad1f3f3f.png)

## CHAPTER 4:ARCHITECTURE AND DESIGN

## 4.2.3 Physical view

Figure 5: Deployment diagram

![Image](output\Project 1 final version-4_artifacts\image_000005_3f30dbd8d5cfe3a3fa3075dd65e86e6ae658e39f1b5cd88c5741ad94425ab0cc.png)

## 4.2.4 Details of each component in a separate section.

## 1. User

## Description

The User component represents the base entity for all system users and provides common functionalities shared by riders and drivers.

Responsibilities

- User authentication.
- Profile management.
- Access system services.
- Maintain personal information.

## 2. Rider

## Description

The Rider component represents passengers who use the system to request transportation services.

Responsibilities

- Select pickup and destination locations.
- Request rides.
- Track driver location.
- View fare estimates.
- Submit ratings and feedback.

## 3. Driver

## Description

The Driver component represents drivers who provide transportation services through the platform.

## Responsibilities

- Accept or reject ride requests.
- View passenger locations.
- Navigate to pickup and destination points.
- Complete trips.
- Update availability status.

## 4. Admin

## Description

The Admin component is responsible for monitoring and managing the overall operation of the system.

## Responsibilities

- View users and drivers information.
- Access trip details and records.
- Review user issues and support requests.
- Approve or reject driver registration requests.
- Manage system settings.

## 5. Trip

## Description

The Trip component manages ride information and controls the trip lifecycle from request to completion.

Responsibilities

- Store trip information.
- Manage trip status.
- Calculate trip fares.
- Support multi-stop trips.
- Maintain trip history.

## 6. Payment

## Description

The Payment component handles payment processing and transaction management.

Responsibilities

- Process cash and card payments.
- Record payment transactions.
- Validate payment status.
- Maintain payment history.

## 7. Vehicle

## Description

The Vehicle component stores vehicle information associated with drivers.

Responsibilities

- Maintain vehicle details.
- Associate vehicles with drivers.
- Store vehicle category information.
- Support vehicle selection during ride requests.

## 8. Location

Description The Location component manages geographical information used throughout the ride booking process.

Responsibilities

- Store pickup locations.
- Store destination locations.
- Manage multi-stop locations.
- Provide location information for route planning.

## 9. GPS System

## Description

The GPS Service component provides location tracking and navigation functionalities required by the system.

Responsibilities

- Determine current locations.
- Support destination navigation.
- Enable real -time trip tracking.
- Calculate routes and distances.
- Support fare estimation.

## 10. Help Request

## Description

The Help Request component manages support requests submitted by users and drivers.

Responsibilities

- Receive support requests.
- Store issue details.
- Provide help center services.
- Track support request status.
- Assist administrators in issue resolution

## 4.3 Software design

## 4.3.1 sequence diagram

## Figure 6: Request Trip

![Image](output\Project 1 final version-4_artifacts\image_000006_4195008f2a91c4d1a2e511b2141d4b982ce49e1373253577e0ab68c4838fb000.png)

Figure 7: Login

![Image](output\Project 1 final version-4_artifacts\image_000007_099b658a4b5b2cdbb8db9410c155f26b07689efff00a572cb6c17afc3b9721ad.png)

## Figure 8: Select Multi-Stop Trip

![Image](output\Project 1 final version-4_artifacts\image_000008_2ccf4479ad870ec460116e19e2c868eb86066659a18e885e991f3f0774f9822b.png)

## 4.3.2 Class diagram

Figure 9: Details level class diagram

![Image](output\Project 1 final version-4_artifacts\image_000009_66aa61946eaf26c86417d6064a6e3c1ccf3259d5a29540e2813724998da23f91.png)

## 4.3.3 ER diagram

Figure 10: ER diagram

![Image](output\Project 1 final version-4_artifacts\image_000010_defd87608b2cd66baed828abec56724bc40a6b0487ee6f540cf568947eb134da.png)

## 4.3.4 State transition diagram

Figure 11: Select Multi Stop Trip

![Image](output\Project 1 final version-4_artifacts\image_000011_126879a2337d62a23b9eb9c4ed258a119c5e96710890f6cd1e6591a9f8bd211a.png)

## 4.4 User interface design (prototype)

Figure 12: Splash Screen

![Image](output\Project 1 final version-4_artifacts\image_000012_6eb835ceaf8102610f8af9191c6b7d0ccdab612f785c3604ba43829692075ead.png)

Figure 14: Onboarding Screen 2

![Image](output\Project 1 final version-4_artifacts\image_000013_30801d296cfe7301def23e371cc6650b15aa2127136b205d0b125ec7779b891b.png)

Figure 13: Onboarding Screen 1

![Image](output\Project 1 final version-4_artifacts\image_000014_43e118e4fc2080c3aefa15b0d4523e7b30806f315391c912bb7a0e4a3efae1be.png)

Figure 15: Onboarding Screen 3

![Image](output\Project 1 final version-4_artifacts\image_000015_87f25ed286ae19b948c3850e4e61b6e6c3adbe1224b94035328f7d3c5b2f8b93.png)

Figure 16: Location Permission

Figure 17: Sign Up

![Image](output\Project 1 final version-4_artifacts\image_000016_1857f453af6a9329b48a6a81fd3c6e2163d3b421488288b8efa71636100931c2.png)

Figure 18: Verification with OTP

![Image](output\Project 1 final version-4_artifacts\image_000017_1d6c611c24ec195c0d5d5325cf76055be4c69a27191fd7cb3f9289243a344f58.png)

![Image](output\Project 1 final version-4_artifacts\image_000018_0b6895b57f3915bec732525b9a6fbc136092951cba6e8cd8b7f8297b7cb5bc17.png)

Figure 19: Select current location

![Image](output\Project 1 final version-4_artifacts\image_000019_259aa2c4031729ec5889b288ffc139bd19cbc01b914f91b775d48c3ec65daf94.png)

Figure 21: Apply destination

![Image](output\Project 1 final version-4_artifacts\image_000020_958ebfa51380428aac11b5d1d07c79e55f34fea49596bd5923fc42b814fac7aa.png)

Figure 20: Select Destination

![Image](output\Project 1 final version-4_artifacts\image_000021_1d88391091fa6751a117aa1db3d7e5f294da35cabbec56314d1941824dd1118c.png)

Figure 22: Choose car type

![Image](output\Project 1 final version-4_artifacts\image_000022_bb8b587a97fd68c0bc0bd163113499edb4ca7f965017dd8c549af0b8d6cb09ff.png)

Figure 23: Enter Promo Code

![Image](output\Project 1 final version-4_artifacts\image_000023_0d424e2149bf80973cde4f055225d55b43b68aa888a83ce59f3c39c5d69e3ed2.png)

Figure 25: Booking Successful

![Image](output\Project 1 final version-4_artifacts\image_000024_bf4a7480c34a83147358dacbeffbace2a1227d70980155b2627f5296dda9a31d.png)

Figure 24: Trip details

![Image](output\Project 1 final version-4_artifacts\image_000025_f2b0c73411463716612873a441b58fe9742c81f798ca7240f356d3da8d967a5f.png)

Figure 26: Live Ride Tracking

![Image](output\Project 1 final version-4_artifacts\image_000026_3afdd59296c16d442f5f5bb86b6fc9627baa4919189cb888b0626e3ee307aaa6.png)

Figure 28: Profile Screen 1

![Image](output\Project 1 final version-4_artifacts\image_000027_1b43cdecbff630adb5c344e5a1964e189e5b408c650a0f5ca7ab13299ce2e468.png)

Figure 27: Chat with Driver

![Image](output\Project 1 final version-4_artifacts\image_000028_5f1086132ac07c86d5c4e736153a53ee841cb64d8bd3eecc7f7e4d55363e01aa.png)

Figure 29: Profile Screen 2

![Image](output\Project 1 final version-4_artifacts\image_000029_6e4aeb3ea0973324c19c044084d9b287642b0eb8d68a7ac1a27ff1ad219fe58e.png)

Figure 30: Rating

![Image](output\Project 1 final version-4_artifacts\image_000030_45d80357cc9d1b7b985fb211c7b9c297e48230b99c671412cc7ba3ba0a36511d.png)

Figure 31: Notifications

![Image](output\Project 1 final version-4_artifacts\image_000031_d8ac069836cd21262689a7e6f4d5277c192f2090dc7354acaffcc7e8a71953a0.png)

Figure 32: Referrals

![Image](output\Project 1 final version-4_artifacts\image_000032_bab2e1c8e4255ece52b4ce1fc70de0e5850e57107a3e6635a1f4140b43eddbc4.png)

Figure 33: Settings

![Image](output\Project 1 final version-4_artifacts\image_000033_b7f426cb3e3a3a60631a84cac00db76354435fc9be6f33b27efff99f16b5f0cc.png)

Figure 34: My Account

![Image](output\Project 1 final version-4_artifacts\image_000034_04a357239016adc5d21f99eb80ea1a2060c2cde6ce4f0668dfe708384be9289a.png)

Figure 35: My Wallet

![Image](output\Project 1 final version-4_artifacts\image_000035_c41bdd2373e083bec28d24fe9537950986d19e48e39ad807cdbd478934947a24.png)

## CHAPTER 5: IMPLEMENTATION PLAN

## 5.1 Description of Implementation

RideX is a mobile -based ride -hailing application that provides users with a smart and efficient transportation experience. The system is designed to offer real-time tracking of rides, allowing passengers to monitor the driver's location throughout the trip to enhance transparency and user confidence.

One of the key features of RideX is the support for multi-stop trips, enabling users to add multiple destinations within a single ride request. This improves flexibility and better accommodates user travel needs.

The system also provides transparent fare estimation before confirming the ride, ensuring that users are fully aware of the expected cost in advance. This enhances trust and reduces uncertainty during the booking process.

In terms of payment methods, RideX supports both cash and card payments, giving users flexible options based on their preference. Additionally, the platform is designed to ensure a safe and secure transportation experience by verifying ride details and maintaining reliable communication between riders and drivers.

Overall, the implementation of RideX focuses on combining usability, transparency, and safety to deliver a modern and reliable ride-hailing solution.

## 5.2 Programming language and technology

The RideX system is planned to be developed using Flutter with Dart as the main programming language. Flutter is selected due to its ability to support crossplatform mobile application development for both Android and iOS using a single codebase.

Firebase is expected to be used as the backend platform to provide authentication, real -time database services, and cloud storage.

Google Maps API will be used to support location services, including real-time tracking and route display.

Development is expected to be carried out using tools such as Visual Studio Code and Android Studio as Integrated Development Environments (IDEs).

Overall, the proposed technology stack provides a scalable and efficient foundation for implementing the RideX system in future development phases.

## 5.3 Version Control

All project files and documentation for RideX are planned to be managed using Git for version control. A GitHub repository will be used to track and store all projectrelated changes.

Commit messages are expected to clearly describe the implemented changes, such as "Added login screen design" or "Updated use case diagram". Each team member will use their own GitHub account to ensure proper tracking of individual contributions within the project.

This approach will help in maintaining version history, improving collaboration, and organizing the development process efficiently during future implementation phases.

## 5.4 Code Snippets and Critical Components

The implementation details and source code will be developed and presented in Project 2 as part of the full system development phase.

## CHAPTER 6: TESTING PLAN

Describe the scope, approach, resources and schedule of intended test activities. It identifies amongst others test items, the features to be tested, the testing tasks, test coverage, degree of tester independence, the test environment, the test design techniques and entry and exit criteria to be used, and the rationale for their choice.

## 6.1 Black -box

Black -box testing techniques are planned to be used to verify the functionality of the RideX system without considering the internal code structure. The testing approach focuses on validating system inputs and outputs based on functional requirements.

The main black -box testing techniques include functional testing and scenariobased testing. These techniques ensure that the system behaves correctly from the user's perspective in different usage scenarios such as login, ride booking, and payment processing.

| Test ID         | TC - 1                                |
|-----------------|---------------------------------------|
| Description     | Verify ride booking request           |
| Input           | Pickup location, Destination location |
| Expected Output | Ride request is successfully created  |

| Test ID         | TC - 01                              |
|-----------------|--------------------------------------|
| Description     | Verify login with valid credentials. |
| Input           | Username="test", Password="123"      |
| Expected Output | Redirect to dashboard.               |

## 6.2 White -box

White -box testing is not applicable at this stage of the project since the system implementation has not yet been developed. The current phase focuses on system analysis and design, while the actual coding and internal logic will be implemented in Project 2.

## 6.3 Testing automation

At the current stage of the RideX project (Project 1), testing automation tools have not yet been applied, as the system is still in the analysis and design phase. The automation process will be implemented in Project 2 during the system development and implementation phase. Conclusion and Results

The conclusion is a required part that closes the document with a brief summary of the study including the problems found and the proposed solution. Most importantly, it should recommend to the readers the benefits of pursuing the project based on the rese archer's analysis.

## CHAPTER 7: CONCLUSION AND RESULTS

## 7.1 Summary of accomplished project

The first phase of the RideX project focused on the analysis and design of a smart ride -hailing system. In Chapter 1, the project motivation, problem statement, objectives, scope, limitations, risks, and project schedule were identified and documented. Chapter 2 presented a literature review of existing ride-hailing systems, highlighting their strengths, weaknesses, and limitations, and explaining how RideX aims to address the identified challenges.

In Chapter 3, stakeholders were identified and analyzed, while both functional and non -functional requirements were defined. UML use case diagrams were developed to represent user interactions with the system. Chapter 4 focused on designing the system architecture and defining the major system components, their relationships, and the overall system design.

Overall, Project 1 successfully established a comprehensive foundation for RideX through requirements analysis, system modeling, architecture design, and planning activities. These deliverables provide a clear roadmap for the implementation and testing phases that will be carried out in Project 2.

## 7.2 Future Work

The next phase of the RideX project (Project 2) will focus on the implementation, testing, and deployment of the proposed system. The planned work includes developing the mobile application using Flutter, integrating Firebase services, implementing user authentication, ride booking, real-time tracking, fare estimation, multi -stop trip functionality, and payment methods.

In addition, comprehensive testing activities will be conducted to verify system functionality, performance, and reliability. The final system will be evaluated against the requirements identified during Project 1.

For future enhancements, RideX can be extended by introducing additional features such as advanced route optimization, ride-sharing options, AI-based demand prediction, loyalty and rewards programs, enhanced analytics dashboards, and support for additional payment gateways. These improvements can further enhance the user experience, increase system efficiency, and support future scalability.

## REFERENCES

- [1] Uber Technologies Inc., "Uber Mobile Application," Uber App. [Online]. Available: https://www.uber.com/app.
- [2] Careem, "Careem Mobile Application," Careem App. [Online]. Available: https://www.careem.com/.
- [3] Jeeny, "Jeeny Ride-Hailing Mobile Application," Jeeny App. [Online]. Available: https://jeeny.com/.
- [4] Uber Technologies Inc., "Uber," Official Website. [Online]. Available: https://www.uber.com/.
- [5] Careem, "Careem," Official Website. [Online]. Available: https://www.careem.com/.
- [6] TaxiF, "TaxiF Ride-Hailing Service," Official Website. [Online]. Available: https://taxif.com/.
- [7] Petra Ride, "Petra Ride Mobile Application," App Store / Official Page. [Online]. Available: https://apps.apple.com/us/app/petra-ride/id1463809354.